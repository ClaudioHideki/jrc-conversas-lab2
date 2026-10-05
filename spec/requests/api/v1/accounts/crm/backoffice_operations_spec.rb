require 'rails_helper'

RSpec.describe 'Backoffice operations integration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests" }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: account, owner: admin, contact: contact,
                             status: 'approved', source_type: 'manual', order_origin: 'direct_sale', snapshot: { generate_contract: true })
  end
  let(:request_record) do
    routing = JrcOperations::BackofficeRouter.new(account: account, order: order, request_kind: 'fulfillment',
                                                 priority: 'normal', preferred_owner: admin).call
    JrcCrm::BackofficeRequest.create!(account: account, sales_order: order, owner: admin, requested_by: admin,
      contact: contact, title: 'Process order', operations_queue: routing.queue, operations_sla_policy: routing.policy)
  end

  before { account.enable_features!('jrc_crm') }

  it 'classifies orders without writes and enforces status, tenant and duplicate guards' do
    order
    get "#{url}/selection_options", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['eligible'].map { |row| row['id'] }).to include(order.id)
    expect(JrcOperations::Queue.where(account: account)).to be_empty
    expect(order.backoffice_requests).to be_empty

    order.update!(status: 'canceled')
    post url, params: { backoffice_request: { sales_order_id: order.id, title: 'Invalid' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    order.update!(status: 'pending')
    post url, params: { backoffice_request: { sales_order_id: order.id, title: 'Pending' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    order.update!(status: 'approved')
    post url, params: { backoffice_request: { sales_order_id: order.id, title: 'Process' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    created = order.backoffice_requests.sole
    expect(created.contact_id).to eq(contact.id)
    expect(created.operations_queue_id).to be_present
    expect(created.sla_due_at).to be_nil
    expect(created.due_at).to be_nil
    get "#{url}/summary", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['within_sla']).to eq(1)
    post url, params: { backoffice_request: { sales_order_id: order.id, title: 'Duplicate' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    other_account = create(:account)
    outsider = create(:user, account: other_account, role: :administrator)
    other_account.enable_features!('jrc_crm')
    post "/api/v1/accounts/#{other_account.id}/crm/backoffice_requests",
         params: { backoffice_request: { sales_order_id: order.id, title: 'Cross tenant' } },
         headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'preserves contract, routing, owner and deadlines when order automation is replayed' do
    JrcCrm::OrderWorkflowSyncService.new(order: order, actor: admin).call
    record = order.backoffice_requests.sole
    expect(record.contract).to be_a(JrcCrm::Contract)
    expect(record.due_at).to be_nil
    record.update!(owner: agent, stage_due_at: 1.day.from_now)
    original = record.attributes.slice('operations_queue_id', 'operations_sla_policy_id', 'owner_id', 'stage_due_at')
    JrcCrm::OrderWorkflowSyncService.new(order: order, actor: admin).call
    expect(order.backoffice_requests.count).to eq(1)
    expect(record.reload.attributes.slice(*original.keys)).to eq(original)
  end

  it 'blocks a pending required document, records validation and stops at the unsigned contract gate' do
    contract = JrcCrm::OrderContractService.new(order: order, actor: admin).call
    request_record.update!(stage: 'documentation', contract: contract, metadata: {
      'document_requirements' => [{ 'key' => 'identity', 'label' => 'Identity', 'required' => true, 'blocking' => true }]
    })
    post "#{url}/#{request_record.id}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{url}/#{request_record.id}/document_status", params: { document_key: 'identity', status: 'approved' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    request_record.documents.attach(io: StringIO.new('test document'), filename: 'identity.txt', content_type: 'text/plain')
    attachment = request_record.documents.first
    post "#{url}/#{request_record.id}/document_status", params: { document_key: 'identity', attachment_id: attachment.id, status: 'approved' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request_record.reload.stage).to eq('contract')
    validation = request_record.metadata['document_validations'].last
    expect(validation).to include('actor_id' => admin.id, 'to' => 'approved', 'attachment_id' => attachment.id)
    expect(validation['at']).to be_present
    post "#{url}/#{request_record.id}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(request_record.reload.stage).to eq('contract')
  end

  it 'blocks advancement at any stage and preserves issue resolution and reopening history' do
    request_record
    post "#{url}/#{request_record.id}/issues", params: { description: 'Missing information', blocking: true }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    issue_id = request_record.reload.metadata['issues'].first['id']
    expect(request_record.status).to eq('blocked')
    post "#{url}/#{request_record.id}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{url}/#{request_record.id}/resolve_issue", params: { issue_id: issue_id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{url}/#{request_record.id}/resolve_issue", params: { issue_id: issue_id, resolution: 'Information received' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request_record.reload.metadata['issues'].first).to include('resolved_by_id' => admin.id, 'resolution' => 'Information received')
    post "#{url}/#{request_record.id}/reopen_issue", params: { issue_id: issue_id, note: 'Needs review' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request_record.reload.metadata['issues'].first['history'].map { |row| row['event'] }).to eq(%w[opened resolved reopened])
    expect(request_record.status).to eq('blocked')
  end

  it 'limits operational configuration writes to administrators' do
    agent_headers = agent.create_new_auth_token
    get "/api/v1/accounts/#{account.id}/crm/operations_queues", headers: agent_headers, as: :json
    expect(response).to have_http_status(:ok)
    post "/api/v1/accounts/#{account.id}/crm/operations_queues", params: { operations_queue: { name: 'Test', code: 'TEST' } },
         headers: agent_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcOperations::Queue.where(account: account, code: 'TEST')).to be_empty
  end
end
