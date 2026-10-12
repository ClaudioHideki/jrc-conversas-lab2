require 'rails_helper'

RSpec.describe 'Commercial E3 and E4 backend contracts', type: :request, approval_core: true, commercial_approvals: true do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:approver) { approval_actor(scope, permissions: ['jrc_approvals_decide', 'jrc_crm']) }
  let(:fixture) { commercial_fixture(scope, author) }
  let(:proposal) { fixture[:proposal] }
  let(:url) { "/api/v1/accounts/#{scope[:account].id}/approvals" }
  let(:headers) { author.user.create_new_auth_token }

  it 'returns a scoped gate DTO without snapshots, floor values, roster, credentials or approval by calculation' do
    proposal
    get "#{url}/gates", params: { key: 'crm.proposal_send', resource_id: proposal.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'POLICY_REQUIRED', 'mode' => 'shadow')
    expect(response.parsed_body.keys).not_to include('snapshot', 'financials', 'minimum_price_cents', 'stage_plan')
  end

  it 'creates a server-captured exception and ignores spoofed price/reference/account/approvers' do
    commercial_policy(scope, author, [approver])
    post "#{url}/requests", params: { approval_request: { key: 'crm.proposal_send', resource_id: proposal.id,
      idempotency_key: 'server', price_reference: { minimum_price_cents: 0 }, account_id: 999,
      approvers: [author.id], evaluated: 'approved' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    record = JrcApprovals::Request.find(response.parsed_body.first['id'])
    expect(record.account_id).to eq(scope[:account].id)
    expect(record.state).to eq('pending')
    expect(record.stage_plan.first['principal_ids']).to eq([approver.id])
    expect(record.snapshot['values']['below_minimum_count']).to eq(1)
  end

  it 'allows a designated approver to read and decide but does not grant CRM ownership or audit access' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    reviewer_headers = approver.user.create_new_auth_token
    get "#{url}/requests/#{record.id}", headers: reviewer_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.keys).not_to include('snapshot', 'stage_plan', 'financials')
    expect(response.parsed_body['allowed_decisions'].first).to include('step_code' => 'review')
    expect(response.parsed_body['allowed_decisions'].first['choices'].first['actions']).to include('approved')
    get "#{url}/requests/#{record.id}/audit", headers: reviewer_headers
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/accounts/#{scope[:account].id}/crm/proposals/#{proposal.id}", headers: reviewer_headers
    expect(response).to have_http_status(:not_found)
    post "#{url}/requests/#{record.id}/decide", params: { decision: { step_code: 'review', decision: 'approved',
      reason: 'Explicit synthetic decision', expected_version: 0, idempotency_key: 'reviewer' } }, headers: reviewer_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload.state).to eq('approved')
    get "#{url}/requests/#{record.id}", headers: reviewer_headers
    expect(response.parsed_body['allowed_decisions']).to eq([])
  end

  it 'paginates only authorized data and preserves the existing array response contract' do
    commercial_policy(scope, author, [approver])
    3.times { |index| commercial_request(scope, author, proposal, idempotency_key: "page-#{index}") }
    get "#{url}/requests", params: { state: 'pending', business_unit_id: scope[:unit].id, page: 2, per_page: 2 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.length).to eq(1)
    expect(response.headers['X-Total-Count']).to eq('3')
    expect(response.headers['X-Page']).to eq('2')
    get "#{url}/requests", params: { page: 0 }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('INVALID_PAGINATION')
  end

  it 'exposes immutable versions and catalog fields only to authorized policy editors' do
    policy = commercial_policy(scope, author, [approver])
    get "#{url}/policies/#{policy.id}/versions", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first).to include('version' => 1, 'digest' => policy.current_version.digest)
    get "#{url}/catalogs", params: { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('key')).to match_array(
      JrcApprovals::CommercialCatalog::EVENTS.keys + [JrcApprovals::CommercialCatalog::PRICE_FAMILY])
    get "#{url}/policies/#{policy.id}", headers: approver.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects unauthorized simulation and validates synthetic context before selection' do
    commercial_policy(scope, author, [approver])
    post "#{url}/requests/simulate", params: { key: 'crm.proposal_send', resource_id: proposal.id },
      headers: approver.user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    before = [JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcCrm::SalesOrder.count, Message.count]
    context = { issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id,
      values: { price_status: 'evaluated', below_minimum_count: 1, context_digest: 'synthetic', signature_evidence: 'not_applicable',
        total_cents: 800, currency: 'BRL', item_count: 1, order_origin: 'proposal_deal', customer_relationship: 'unknown' } }
    post "#{url}/requests/simulate", params: { key: 'crm.proposal_send', context: context }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['effects']).to eq([])
    expect(response.parsed_body['versions'].first['plan'].first['principal_ids']).to eq([approver.id])
    expect([JrcApprovals::Request.count, JrcApprovals::Decision.count, JrcCrm::SalesOrder.count, Message.count]).to eq(before)
    context[:values][:below_minimum_count] = 'one'
    post "#{url}/requests/simulate", params: { key: 'crm.proposal_send', context: context }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('INVALID_TYPED_VALUE')
  end

  it 'does not permit cross-tenant, cross-company or cross-unit gate reads' do
    proposal
    other_scope = approval_scope(account: scope[:account])
    outsider = approval_actor(other_scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'])
    get "#{url}/gates", params: { key: 'crm.proposal_send', resource_id: proposal.id }, headers: outsider.user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    alien = approval_scope
    alien_author = approval_actor(alien, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'])
    get "/api/v1/accounts/#{alien[:account].id}/approvals/gates", params: { key: 'crm.proposal_send', resource_id: proposal.id },
      headers: alien_author.user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'denies direct/manual order bypass and rolls back every native order/approval side effect' do
    proposal
    commercial_policy(scope, author, [approver], key: 'crm.order_price')
    commercial_mode(scope[:account], 'crm.order_price', 'enforcement')
    before = [JrcCrm::SalesOrder.count, JrcCrm::BackofficeRequest.count, JrcCrm::AuditEvent.count]
    post "/api/v1/accounts/#{scope[:account].id}/crm/sales_orders", params: { sales_order: {
      contact_id: fixture[:contact].id, business_unit_id: scope[:unit].id, status: 'pending',
      items: [{ product_id: fixture[:product].id, name: fixture[:product].name, quantity: 1, unit_cents: 1000,
        discount_cents: 200, snapshot: { billing_model: 'one_time', unit_name: 'unidade', price_reference: { minimum_price_cents: 0 } } }]
    } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict), response.body
    expect(response.parsed_body['code']).to eq('APPROVAL_REQUIRED')
    expect([JrcCrm::SalesOrder.count, JrcCrm::BackofficeRequest.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'uses native editing endpoints to invalidate price approval without allowing fields from another resource' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    item = proposal.proposal_items.first
    patch "/api/v1/accounts/#{scope[:account].id}/crm/proposals/#{proposal.id}/items/#{item.id}",
      params: { item: { quantity: 2, price_reference: { minimum_price_cents: 0 } } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(record.reload.state).to eq('stale')
    expect(item.reload.quantity).to eq(2)
    expect(record.decisions.count).to eq(1)
  end

  it 'invalidates the existing request after an authorized native floor-reference edit' do
    commercial_policy(scope, author, [approver])
    record = commercial_request(scope, author, proposal).first
    approval_vote(scope, approver, record)
    patch "/api/v1/accounts/#{scope[:account].id}/crm/products/#{fixture[:product].id}",
      params: { product: { minimum_price_cents: 950 } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(record.reload.state).to eq('stale')
    expect(record.decisions.count).to eq(1)
  end

  it 'records the customer signature independently and holds activation/release until company evidence and approval' do
    proposal
    order = JrcCrm::SalesOrder.create!(account: scope[:account], owner: author.user, created_by: author.user,
      contact: fixture[:contact], business_unit: scope[:unit], source_type: 'manual', status: 'pending')
    terms = proposal.financial_summary
    order.update!(JrcCrm::OrderFinancials.attributes_for(terms).merge(snapshot: JrcCrm::OrderFinancials.snapshot_for(terms)))
    terms[:items].each { |item| order.order_items.create!(item) }
    JrcCrm::OrderApprovalService.new(order: order, actor: author.user)
      .decide!(request: order.backoffice_requests.find_by!(request_kind: 'approval'), decision: 'approved')
    contract = JrcCrm::Contract.create!(account: scope[:account], owner: author.user, sales_order: order,
      contact: fixture[:contact], business_unit: scope[:unit])
    commercial_policy(scope, author, [approver], key: 'contracts.company_signature')
    commercial_mode(scope[:account], 'contracts.company_signature', 'enforcement')
    file = Tempfile.new(['synthetic-customer-signature', '.pdf'])
    file.binmode
    file.write(JrcCrm::ProposalPdfService.new(proposal).call)
    file.close
    upload = Rack::Test::UploadedFile.new(file.path, 'application/pdf')
    post "/api/v1/accounts/#{scope[:account].id}/crm/contracts/#{contract.id}/register_manual_signature",
      params: { signed_by_name: 'Synthetic customer signer', signed_at: Time.current.iso8601, signed_file: upload }, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(contract.reload.signature_status).to eq('signed')
    expect(contract.signed_document).to be_attached
    expect(contract.status).to eq('awaiting_signature')
    patch "/api/v1/accounts/#{scope[:account].id}/crm/contracts/#{contract.id}",
      params: { contract: { status: 'active' } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(contract.reload.status).to eq('awaiting_signature')
    patch "/api/v1/accounts/#{scope[:account].id}/crm/sales_orders/#{order.id}",
      params: { sales_order: { status: 'separating' } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(order.reload.status).to eq('approved')
  ensure
    file&.unlink
  end
end
