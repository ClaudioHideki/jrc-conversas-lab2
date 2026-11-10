require 'rails_helper'

RSpec.describe 'Native CS handoff from project completion', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: contact, owner: actor) }
  let(:project) do
    JrcProjects::Project.create!(account: account, owner: actor, contact: contact, key: 'CS_TEST',
                                 name: 'Synthetic implementation', status: 'completed')
  end
  let(:handoff) do
    JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: project.class.name, source_id: project.id)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/handoffs/#{handoff.id}/decide" }
  let(:headers) { actor.create_new_auth_token }
  let(:checklist) { %w[contract products contacts objectives promises pending_items].index_with(true) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_projects') }

  it 'revalidates completion at acceptance and rolls back a decision on a reopened native implementation' do
    handoff
    project.update!(status: 'active')
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Source was reopened', checklist: checklist }
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'accepts a currently completed native implementation with the complete checklist and real decision actor' do
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Implementation reviewed', checklist: checklist }
    expect(response).to have_http_status(:ok), response.body
    expect(handoff.reload).to have_attributes(status: 'accepted', decided_by_id: actor.id, checklist: checklist)
  end

  it 'allows a reasoned rejection after reopening without falsely accepting the delivery' do
    handoff
    project.update!(status: 'active')
    post url, headers: headers, as: :json, params: { status: 'rejected', reason: 'Implementation incomplete', checklist: { contract: false } }
    expect(response).to have_http_status(:ok), response.body
    expect(handoff.reload).to have_attributes(status: 'rejected', reason: 'Implementation incomplete')
  end

  it 'refuses completed implementations whose linked v2 order still lacks current signature evidence' do
    account.enable_features!('jrc_crm')
    order = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved')
    contract = account.jrc_crm_contracts.create!(sales_order: order, contact: contact, owner: actor)
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, contact: contact, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', stage: 'contract', title: 'Synthetic linked implementation',
                                                metadata: { implementation_project_id: project.id.to_s, finance_required: false })
    handoff
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Incomplete legal source', checklist: checklist }
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'does not use a linked order for a different customer as the commercial origin of the completed project' do
    account.enable_features!('jrc_crm')
    other_contact = create(:contact, account: account)
    order = account.jrc_crm_sales_orders.create!(owner: actor, contact: other_contact, status: 'approved')
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contact: other_contact, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', title: 'Synthetic wrong customer link',
                                                metadata: { implementation_project_id: project.id.to_s })
    handoff
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Forged customer origin', checklist: checklist }
    expect(response).to have_http_status(:not_found)
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'does not accept or disclose a legacy case referencing a foreign project' do
    other = create(:account)
    foreign = JrcProjects::Project.create!(account: other, owner: create(:user, account: other), key: 'CS_FOREIGN', name: 'Foreign synthetic source')
    handoff.update!(source_id: foreign.id)
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Forged source', checklist: checklist }
    expect(response).to have_http_status(:not_found)
    expect(handoff.reload.attributes).to eq(before)
  end

  it 'denies a declared native order origin from another account instead of treating it as a standalone project' do
    other = create(:account)
    foreign = other.jrc_crm_sales_orders.create!(owner: create(:user, account: other), status: 'approved')
    project.update!(idempotency_key: "crm-order-implementation-#{foreign.id}")
    handoff
    before = handoff.attributes.deep_dup
    post url, headers: headers, as: :json, params: { status: 'accepted', reason: 'Forged native order reference', checklist: checklist }
    expect(response).to have_http_status(:not_found)
    expect(handoff.reload.attributes).to eq(before)
  end
end
