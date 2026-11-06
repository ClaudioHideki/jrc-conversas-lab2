require 'rails_helper'

RSpec.describe JrcRelationship::WithdrawalHandoffProjects, type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: analyst) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:project_key) { SecureRandom.uuid }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: analyst,
                                       attributes: { name: 'Synthetic CS handoff implementation', contact_id: contact.id },
                                       idempotency_key: project_key)
  end
  let(:handoff) do
    JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: project.class.name, source_id: project.id)
  end
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:headers) { actor.create_new_auth_token }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects') }

  it 'keeps an actually prepared native project handoff linked when implementation is reopened' do
    project.update!(status: 'completed')
    post "#{base}/handoffs", headers: headers, as: :json,
                             params: { assignment_id: assignment.id, source_type: project.class.name, source_id: project.id }
    expect(response).to have_http_status(:created)
    handoff_id = response.parsed_body.fetch('id')
    checklist = %w[contract products contacts objectives promises pending_items].index_with(true)
    post "#{base}/handoffs/#{handoff_id}/decide", headers: headers, as: :json,
                                                  params: { status: 'accepted', reason: 'Synthetic native CS acceptance', checklist: checklist }
    expect(response).to have_http_status(:ok)
    accepted = JrcRelationship::HandoffCase.find(handoff_id).attributes
    project.update!(status: 'active')
    task = JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                           attributes: { title: 'Native reopened implementation task', assignee_id: analyst.id },
                                           correlation_id: SecureRandom.uuid)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts)).to include('projects' => 1, 'project_tasks' => 1)
    get "#{base}/team/#{analyst.id}/native_responsibilities", headers: headers, params: { kind: 'project_tasks' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([task.id])
    expect([project.reload.owner_id, task.reload.assignee_id]).to eq([analyst.id, analyst.id])
    expect(JrcRelationship::HandoffCase.find(handoff_id).attributes).to eq(accepted)
  end

  it 'does not treat a rejected project handoff as effective CS responsibility' do
    handoff
    post "#{base}/handoffs/#{handoff.id}/decide", headers: headers, as: :json,
                                                  params: { status: 'rejected', reason: 'Synthetic cancelled CS intake',
                                                            checklist: { contract: false } }
    expect(response).to have_http_status(:ok)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts).fetch('projects')).to eq(0)
    expect(project.reload.owner_id).to eq(analyst.id)
  end

  it 'keeps inactive historical portfolios out of the current handoff responsibility scope' do
    handoff
    assignment.update!(status: 'inactive')
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts).fetch('projects')).to eq(0)
  end

  it 'uses the canonical Backoffice implementation order when the formal source is an order' do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contact: contact, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', title: 'Synthetic native implementation source',
                                                metadata: { implementation_project_id: project.id.to_s })
    JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
    expect(review.fetch(:counts).fetch('projects')).to eq(1)
  end

  context 'with native order implementation identity' do
    let(:project_key) { "crm-order-implementation-#{order.id}" }

    it 'recognizes the existing canonical native order identity without a Backoffice request' do
      project
      JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
      review = JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id)
      expect(review.fetch(:counts).fetch('projects')).to eq(1)
    end

    it 'does not trust the key over a conflicting canonical Backoffice origin or silently report zero' do
      other = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved')
      account.jrc_crm_backoffice_requests.create!(sales_order: other, contact: contact, owner: actor, requested_by: actor,
                                                  request_kind: 'fulfillment', title: 'Synthetic conflicting implementation',
                                                  metadata: { implementation_project_id: project.id.to_s })
      JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: order.class.name, source_id: order.id)
      expect { JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id) }.to raise_error(ArgumentError, /native source review/)
    end
  end

  it 'denies a wrong-customer native order even when the implementation metadata names the local project' do
    other = create(:contact, account: account)
    wrong_order = account.jrc_crm_sales_orders.create!(owner: actor, contact: other, status: 'approved')
    account.jrc_crm_backoffice_requests.create!(sales_order: wrong_order, contact: other, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', title: 'Synthetic wrong customer implementation',
                                                metadata: { implementation_project_id: project.id.to_s })
    JrcRelationship::HandoffCase.create!(account: account, assignment: assignment, source_type: wrong_order.class.name, source_id: wrong_order.id)
    expect { JrcRelationship::WithdrawalReadiness.new(context).call(analyst.id) }.to raise_error(Pundit::NotAuthorizedError)
  end
end
