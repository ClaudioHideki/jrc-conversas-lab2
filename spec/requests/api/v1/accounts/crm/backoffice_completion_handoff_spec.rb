require 'rails_helper'

RSpec.describe 'Backoffice completion to native CS handoff', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'Synthetic CS customer') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contact: contact, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', stage: 'finance', title: 'Synthetic completed CS operation',
                                                metadata: { finance_required: false })
  end
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, owner: actor) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/completion_handoff" }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'opens the exact native origin even when its approved order is not in the completed-order choices and prepares once by explicit POST' do
    assignment
    operation.advance!(actor: actor)
    baseline = [JrcRelationship::Assignment.count, JrcRelationship::HandoffCase.count, JrcRelationship::PlaybookExecution.count]
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('available' => true, 'assignment_id' => assignment.id,
                                            'source_type' => 'JrcCrm::SalesOrder', 'source_id' => order.id, 'handoff_id' => nil)
    expect([JrcRelationship::Assignment.count, JrcRelationship::HandoffCase.count, JrcRelationship::PlaybookExecution.count]).to eq(baseline)
    get "#{base}/portfolio/#{assignment.id}/work_context", headers: headers,
                                                           params: { source_type: 'JrcCrm::SalesOrder', source_id: order.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['handoff_sources']).to include('type' => 'JrcCrm::SalesOrder', 'id' => order.id, 'label' => order.order_number)
    2.times do
      post "#{base}/handoffs", headers: headers, as: :json,
                               params: { assignment_id: assignment.id, source_type: 'JrcCrm::SalesOrder', source_id: order.id }
      expect(response).to have_http_status(:created), response.body
    end
    expect(JrcRelationship::HandoffCase.where(account: account, source_type: order.class.name, source_id: order.id).count).to eq(1)
  end

  it 'locates an existing native handoff without changing its decision or creating another portfolio' do
    operation.advance!(actor: actor)
    handoff = JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
    before = handoff.attributes.deep_dup
    get url, headers: headers
    expect(response.parsed_body).to include('available' => true, 'handoff_id' => handoff.id, 'handoff_status' => 'pending')
    get "#{base}/handoffs", headers: headers, params: { assignment_id: assignment.id, handoff_id: handoff.id }
    expect(response.parsed_body['payload'].pluck('id')).to eq([handoff.id])
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'persists the explicit native CS acceptance and does not permit rewriting its decision' do
    operation.advance!(actor: actor)
    handoff = JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
    checklist = %w[contract products contacts objectives promises pending_items].index_with(true)
    post "#{base}/handoffs/#{handoff.id}/decide", headers: headers, as: :json,
                                                  params: { status: 'accepted', reason: 'Reviewed synthetic CS delivery', checklist: checklist }
    expect(response).to have_http_status(:ok), response.body
    expect(handoff.reload).to have_attributes(status: 'accepted', decided_by_id: actor.id, checklist: checklist)
    before = handoff.attributes.deep_dup
    post "#{base}/handoffs/#{handoff.id}/decide", headers: headers, as: :json,
                                                  params: { status: 'rejected', reason: 'Cannot rewrite', checklist: checklist }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'rejects acceptance of a prepared handoff when the original operation was reopened' do
    operation.advance!(actor: actor)
    handoff = JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
    operation.update!(status: 'in_progress', stage: 'finance', completed_at: nil)
    checklist = %w[contract products contacts objectives promises pending_items].index_with(true)
    post "#{base}/handoffs/#{handoff.id}/decide", headers: headers, as: :json,
                                                  params: { status: 'accepted', reason: 'Stale delivery',
                                                            checklist: checklist }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(handoff.reload).to have_attributes(status: 'pending', decided_by_id: nil)
  end

  it 'leaves companies without an authorized existing portfolio blocked rather than creating one during preview' do
    operation.advance!(actor: actor)
    before = JrcRelationship::Assignment.count
    get url, headers: headers
    expect(response.parsed_body).to eq('available' => false, 'code' => 'HANDOFF_CONTEXT_UNAVAILABLE')
    expect(JrcRelationship::Assignment.count).to eq(before)
  end

  it 'requires current native v2 signature evidence while preserving legacy v1 manual signature eligibility' do
    assignment
    operation.advance!(actor: actor)
    # A synthetic post-completion source change must not become a legal receipt.
    contract = account.jrc_crm_contracts.create!(sales_order: order, contact: contact, owner: actor)
    contract.signed_document.attach(io: StringIO.new('%PDF-1.4 synthetic legacy signed file'),
                                    filename: 'synthetic-legacy.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'Synthetic legacy signer')
    operation.update!(contract: contract, workflow_version: 2)
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('available' => false, 'code' => 'HANDOFF_DEPENDENCY_PENDING')
    operation.update!(workflow_version: 1)
    get url, headers: headers
    expect(response.parsed_body).to include('available' => true, 'assignment_id' => assignment.id)
  end

  it 'refuses CS acceptance after a prepared order gains a v2 signature dependency without version-bound evidence' do
    operation.advance!(actor: actor)
    handoff = JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
    contract = account.jrc_crm_contracts.create!(sales_order: order, contact: contact, owner: actor)
    operation.update!(contract: contract, workflow_version: 2)
    before = handoff.attributes.deep_dup
    checklist = %w[contract products contacts objectives promises pending_items].index_with(true)
    post "#{base}/handoffs/#{handoff.id}/decide", headers: headers, as: :json,
                                                  params: { status: 'accepted', reason: 'Synthetic changed legal dependency', checklist: checklist }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'requires an operationally completed request and current native Relationship team permission' do
    assignment
    get url, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    operation.advance!(actor: actor)
    role = create(:custom_role, account: account, permissions: %w[jrc_crm contact_manage jrc_relationship_view])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    get url, headers: headers
    expect(response.parsed_body).to eq('available' => false, 'code' => 'HANDOFF_PERMISSION_REQUIRED')
    expect(response.body).not_to include('assignment_id', 'source_id')
  end

  it 'rejects a foreign tenant and a forged operational owner before disclosing any CS context' do
    assignment
    operation.advance!(actor: actor)
    foreign = create(:user, account: create(:account), role: :administrator)
    get url, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    other = create(:user, account: account, role: :agent)
    get url, headers: other.create_new_auth_token, params: { user_id: actor.id, owner_id: actor.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'rechecks current native issuer/unit coverage after revocation' do
    issuer = account.master_companies.create!(name: 'Synthetic internal issuer', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Synthetic CS unit', code: 'completion-cs', company_id: issuer.id)
    grant = JrcCrm::UserBusinessUnit.create!(account: account, user: actor, company: issuer, business_unit: unit,
                                             scope: 'BUSINESS_UNIT', structure_managed: true)
    order.update!(business_unit: unit)
    operation.update!(business_unit: unit)
    assignment.update!(business_unit: unit)
    operation.advance!(actor: actor)
    get url, headers: headers
    expect(response.parsed_body['available']).to be(true)
    grant.update!(active: false)
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'uses native customer and origin scopes for exact references instead of trusting query IDs or types' do
    assignment
    operation.advance!(actor: actor)
    another = account.jrc_crm_sales_orders.create!(owner: actor, contact: create(:contact, account: account), status: 'completed')
    get "#{base}/portfolio/#{assignment.id}/work_context", headers: headers,
                                                           params: { source_type: 'JrcCrm::SalesOrder', source_id: another.id }
    expect(response).to have_http_status(:not_found)
    get "#{base}/portfolio/#{assignment.id}/work_context", headers: headers, params: { source_type: 'User', source_id: actor.id }
    expect(response).to have_http_status(:unprocessable_entity)
    get "#{base}/portfolio/#{assignment.id}/work_context", headers: headers,
                                                           params: { source_type: 'JrcCrm::SalesOrder', source_id: '-1' }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves native go-live and signature prerequisites after reopening the operation' do
    assignment
    operation.advance!(actor: actor)
    operation.update!(status: 'in_progress', stage: 'finance', completed_at: nil)
    post "#{base}/handoffs", headers: headers, as: :json,
                             params: { assignment_id: assignment.id, source_type: order.class.name, source_id: order.id }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::HandoffCase.where(account: account)).to be_empty
  end
end
