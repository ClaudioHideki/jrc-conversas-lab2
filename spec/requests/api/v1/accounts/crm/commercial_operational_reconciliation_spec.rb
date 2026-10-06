require 'rails_helper'

RSpec.describe 'Commercial operational reconciliation', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: agent, created_by: agent, contact: contact,
    source_type: 'manual', order_origin: 'direct_sale', status: 'pending') }
  let(:approval) { order.backoffice_requests.find_by!(request_kind: 'approval') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  it 'creates exactly one native approval request and preserves a recorded rejection on retry' do
    expect(approval.metadata['source']).to eq('order_approval')
    JrcCrm::OrderApprovalService.new(order: order, actor: admin).decide!(request: approval, decision: 'rejected', reason: 'Revisar condições')
    2.times { JrcCrm::OrderWorkflowSyncService.new(order: order, actor: agent).call }
    expect(order.backoffice_requests.where(request_kind: 'approval').count).to eq(1)
    expect(approval.reload.status).to eq('rejected')
    expect(order.reload.status).to eq('pending')
    expect(order.contracts).to be_empty
  end
  it 'rejects direct seller approval and keeps downstream records absent' do
    patch "#{base}/sales_orders/#{order.id}", params: { sales_order: { status: 'approved' } }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload).to be_pending
    expect(order.contracts).to be_empty
  end
  it 'enforces administrator permission for the native approval decision' do
    post "#{base}/backoffice_requests/#{approval.id}/decide_order", params: { decision: 'approved' }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(order.reload).to be_pending
  end
  it 'records administrator approval atomically with the order and its audit trail' do
    post "#{base}/backoffice_requests/#{approval.id}/decide_order", params: { decision: 'approved' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(order.reload).to be_approved
    expect(approval.reload).to be_approved
    expect(order.backoffice_requests.where(request_kind: 'fulfillment').count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: order.class.name, resource_id: order.id, event_type: 'order_updated').count).to eq(1)
  end
  it 'requires a reason for return without changing the order or creating contracts' do
    post "#{base}/backoffice_requests/#{approval.id}/decide_order", params: { decision: 'returned' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload).to be_pending
    expect(approval.reload).to be_pending
  end
  it 'rejects contract creation before order approval' do
    post "#{base}/contracts", params: { contract: { sales_order_id: order.id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.contracts).to be_empty
  end
  it 'prevents bypassing order approval in direct model writes' do
    expect(order.update(status: 'approved')).to be(false)
    expect(order.reload).to be_pending
  end
end
