require 'rails_helper'

RSpec.describe 'CRM commercial flow integration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:contact) { create(:contact, account: account) }
  let(:orders_url) { "/api/v1/accounts/#{account.id}/crm/sales_orders" }

  before do
    account.enable_features!('jrc_crm')
    JrcCrm::CommissionProgram.create!(
      account: account,
      name: 'Plano padrão',
      release_condition: 'order_approved',
      active: true,
      rules: { base: 'total_cents', rate_percent: 10, tiers: [] }
    )
    JrcCrm::SalesGoal.create!(
      account: account,
      name: 'Meta mensal',
      status: 'active',
      scope_kind: 'company',
      metric: 'revenue',
      period_start: Time.zone.today.beginning_of_month,
      period_end: Time.zone.today.end_of_month,
      target_cents: 10_000_000
    )
  end

  # Exercise the recorded Backoffice decision instead of bypassing approval.
  def approve_order(order_id)
    order = JrcCrm::SalesOrder.find(order_id)
    expect(order).to be_pending
    expect(order.commissions).to be_empty
    approval = order.backoffice_requests.find_by!(request_kind: 'approval')
    post "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{approval.id}/decide_order",
         params: { decision: 'approved' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(order.reload).to be_approved
    order
  end

  it 'recalculates order totals and propagates the new value to goals, commissions and backoffice' do
    post orders_url,
         params: {
           sales_order: {
             owner_id: admin.id, contact_id: contact.id,
             source_type: 'manual',
             status: 'pending',
             sold_at: Time.current,
             discount_cents: 0,
             shipping_cents: 0,
             items: [
               { name: 'Licença', quantity: 1, unit_cents: 4_000_000, one_time_cents: 4_000_000,
                 recurring_cents: 200_000 }
             ]
           }
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    order_id = response.parsed_body['id']
    expect(response.parsed_body.slice('products_cents', 'monthly_cents', 'total_cents')).to eq(
      'products_cents' => 4_000_000, 'monthly_cents' => 200_000, 'total_cents' => 4_000_000
    )

    patch "#{orders_url}/#{order_id}",
          params: {
            sales_order: {
              items: [
                { name: 'Licença', quantity: 1, unit_cents: 5_000_000, one_time_cents: 5_000_000,
                  recurring_cents: 250_000 }
              ]
            }
          },
          headers: headers,
          as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.slice('products_cents', 'monthly_cents', 'total_cents')).to eq(
      'products_cents' => 5_000_000, 'monthly_cents' => 250_000, 'total_cents' => 5_000_000
    )

    order = approve_order(order_id)
    commission = order.commissions.sole
    backoffice_request = order.backoffice_requests.find_by!(request_kind: 'fulfillment')
    expect(commission.attributes.slice('base_cents', 'commission_cents', 'status')).to eq(
      'base_cents' => 5_000_000, 'commission_cents' => 500_000, 'status' => 'pending_approval'
    )
    expect(backoffice_request.metadata.slice('order_total_cents', 'monthly_cents')).to eq(
      'order_total_cents' => 5_000_000, 'monthly_cents' => 250_000
    )

    get "/api/v1/accounts/#{account.id}/crm/goals/dashboard",
        params: { start_date: Time.zone.today.beginning_of_month, end_date: Time.zone.today.end_of_month },
        headers: headers,
        as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.slice('realized_cents', 'attainment')).to eq(
      'realized_cents' => 5_000_000, 'attainment' => 50.0
    )
  end

  it 'reverses unpaid commission and cancels the operational request when the order is canceled' do
    post orders_url,
         params: {
           sales_order: {
             owner_id: admin.id,
             source_type: 'manual',
             status: 'pending',
             contact_id: contact.id,
             items: [{ name: 'Projeto', quantity: 1, unit_cents: 100_000, one_time_cents: 100_000 }]
           }
         },
         headers: headers,
         as: :json
    expect(response).to have_http_status(:created)
    order = approve_order(response.parsed_body.fetch('id'))

    patch "#{orders_url}/#{order.id}", params: { sales_order: { status: 'canceled' } }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(order.commissions.sole.reload).to be_reversed
    expect(order.backoffice_requests.find_by!(request_kind: 'fulfillment').reload).to be_canceled
  end

  it 'persists commission plans through the API after refresh' do
    products = [
      create(:jrc_crm_product, account: account, sku: 'PLAN-CRM-1'),
      create(:jrc_crm_product, account: account, sku: 'PLAN-CRM-2')
    ]
    url = "/api/v1/accounts/#{account.id}/crm/commission_programs"
    post url,
         params: {
           commission_program: {
             name: 'Plano produtos e equipe',
             release_condition: 'payment_received',
             active: true,
             rules: {
               base: 'monthly_cents',
               rate_percent: 7.5,
               product_ids: products.map(&:id),
               user_ids: [admin.id],
               team_ids: [],
               tiers: [{ min_cents: 100_000, max_cents: nil, rate_percent: 9 }]
             }
           }
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    program_id = response.parsed_body['id']

    get url, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    persisted = response.parsed_body.find { |row| row['id'] == program_id }
    expect(persisted.dig('rules', 'base')).to eq('monthly_cents')
    expect(persisted.dig('rules', 'tiers', 0, 'rate_percent')).to eq(9)
  end

  it 'creates an invoice, records payment and completes the backoffice flow' do
    post orders_url,
         params: {
           sales_order: {
             owner_id: admin.id,
             status: 'pending',
             contact_id: contact.id,
             items: [{ name: 'Implantação', quantity: 1, unit_cents: 300_000, one_time_cents: 300_000 }]
           }
         },
         headers: headers,
         as: :json
    expect(response).to have_http_status(:created)
    order = approve_order(response.parsed_body.fetch('id'))

    post "/api/v1/accounts/#{account.id}/crm/invoices",
         params: { invoice: { sales_order_id: order.id, status: 'issued', due_on: 30.days.from_now.to_date } },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    invoice_id = response.parsed_body['id']
    expect(response.parsed_body['balance_cents']).to eq(300_000)

    post "/api/v1/accounts/#{account.id}/crm/payments",
         params: {
           payment: {
             invoice_id: invoice_id,
             amount_cents: 300_000,
             paid_at: Time.current,
             method: 'pix',
             reconciliation_status: 'reconciled'
           }
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    expect(JrcCrm::Invoice.find(invoice_id)).to be_paid
    request = order.backoffice_requests.find_by!(request_kind: 'fulfillment').reload
    expect(request.attributes.slice('stage', 'status')).to eq('stage' => 'completed', 'status' => 'completed')
  end

  it 'locks approved financial terms throughout documentation and after deferred contract creation' do
    product = create(:jrc_crm_product, account: account, requires_contract: true,
      document_rules: [{ 'key' => 'identity', 'label' => 'Synthetic identity', 'source' => 'manual', 'required' => true, 'blocking' => true }])
    post orders_url, params: { sales_order: {
      contact_id: contact.id, status: 'pending', items: [{
        product_id: product.id, name: 'Synthetic contracted service', quantity: 1, unit_cents: 100_000,
        one_time_cents: 100_000, recurring_cents: 2000
      }]
    } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    order = approve_order(response.parsed_body.fetch('id'))
    request = order.backoffice_requests.find_by!(request_kind: 'fulfillment')
    path = "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{request.id}"
    expect(request.workflow_version).to eq(2)
    expect(request.stage).to eq('analysis')
    expect(order.contracts).to be_empty
    before = order.financial_summary.deep_dup
    items_before = order.order_items.order(:id).map(&:attributes)
    patch "#{orders_url}/#{order.id}", params: { sales_order: { items: [{
      name: 'Synthetic attempted change', quantity: 1, unit_cents: 1, one_time_cents: 1
    }] } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('Condicoes aceitas/contratadas sao imutaveis')
    expect(order.reload.financial_summary).to eq(before)
    expect(order.order_items.order(:id).map(&:attributes)).to eq(items_before)
    expect(order.commissions.sole.base_cents).to eq(100_000)
    expect(order.contracts).to be_empty

    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request.reload.stage).to eq('documentation')
    patch "#{orders_url}/#{order.id}", params: { sales_order: { discount_cents: 100 } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload.financial_summary).to eq(before)
    expect(order.contracts).to be_empty
    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    file = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf')
    post "#{path}/documents", params: { files: [file] }, headers: headers
    expect(response).to have_http_status(:created)
    attachment_id = response.parsed_body.fetch('documents').first.fetch('id')
    post "#{path}/document_status", params: { document_key: 'identity', attachment_id: attachment_id, status: 'approved' },
      headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    # Preserve legacy status recording, while proving it cannot satisfy the v2
    # release gate or substitute for a version, technical scan and human decision.
    expect(request.reload.metadata.dig('document_statuses', 'identity')).to eq('approved')
    expect(JrcBackoffice::DocumentGate.statuses(request).fetch('identity')).to eq('pending')
    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(request.reload.stage).to eq('documentation')
    expect(order.contracts).to be_empty
    post "#{path}/document_versions", params: { document_key: 'identity', file: file, idempotency_key: SecureRandom.uuid }, headers: headers
    expect(response).to have_http_status(:created), response.body
    version = JrcBackoffice::DocumentVersion.find(response.parsed_body.fetch('id'))
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(version.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => version.sha256
    )
    JrcBackoffice::DocumentPreanalysisJob.perform_now(version.id)
    expect(version.reload.decisions).to be_empty
    post "#{path}/document_versions/#{version.id}/decision", params: { status: 'approved', reason: 'SYNTHETIC reviewed identity' },
      headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request.reload.stage).to eq('contract')
    contract = order.contracts.sole
    expect(contract).to be_draft
    contract_snapshot = contract.lifecycle_metadata.deep_dup
    patch "#{orders_url}/#{order.id}", params: { sales_order: { shipping_cents: 100, snapshot: { shipping_mode: 'separate' } } },
      headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload.financial_summary).to eq(before)
    expect(contract.reload.lifecycle_metadata).to eq(contract_snapshot)
    expect(order.commissions.sole.base_cents).to eq(100_000)
  end

  it 'keeps approved terms locked while the operational release awaits its configured approval policy' do
    post orders_url, params: { sales_order: { contact_id: contact.id, items: [
      { name: 'Synthetic recurring service', quantity: 1, unit_cents: 100_000, one_time_cents: 100_000, recurring_cents: 2000 }
    ] } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    order = approve_order(response.parsed_body.fetch('id'))
    request = order.backoffice_requests.find_by!(request_kind: 'fulfillment')
    path = "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{request.id}"
    patch path, params: { backoffice_request: { metadata: { approval_required: true } } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request.reload.stage).to eq('documentation')
    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(request.reload.stage).to eq('approval')
    expect(order.contracts).to be_empty
    before = order.financial_summary.deep_dup
    patch "#{orders_url}/#{order.id}", params: { sales_order: { discount_cents: 100 } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload.financial_summary).to eq(before)
    post "#{path}/advance", headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(request.reload.stage).to eq('approval')
    expect(order.contracts).to be_empty
  end

  it 'keeps legacy contractual terms locked without a recorded order approval' do
    order = JrcCrm::SalesOrder.create!(account: account, owner: admin, contact: contact, status: 'approved', source_type: 'manual')
    request = JrcCrm::BackofficeRequest.create!(account: account, sales_order: order, owner: admin,
      requested_by: admin, request_kind: 'fulfillment', title: 'Synthetic legacy request', stage: 'analysis')
    # Represent an existing row retained as version 1 by the upgrade migration.
    request.update_column(:workflow_version, 1)
    contract = JrcCrm::Contract.create!(account: account, owner: admin, contact: contact, sales_order: order)
    expect(order.backoffice_requests.where(request_kind: 'approval')).to be_empty
    expect(request.workflow_stages).to eq(JrcCrm::BackofficeRequest::STAGES)
    before = order.financial_summary.deep_dup
    patch "#{orders_url}/#{order.id}", params: { sales_order: { shipping_cents: 100 } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload.financial_summary).to eq(before)
    expect(order.contracts.reload).to contain_exactly(contract)
  end
end
