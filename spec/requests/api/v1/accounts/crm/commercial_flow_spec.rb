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

  it 'rejects later financial changes after recorded approval creates a contractual snapshot' do
    post orders_url, params: { sales_order: {
      contact_id: contact.id, status: 'approved', items: [{
        name: 'Synthetic contracted service', quantity: 1, unit_cents: 100_000,
        one_time_cents: 100_000, recurring_cents: 2000
      }]
    } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    order = approve_order(response.parsed_body.fetch('id'))
    contract = order.contracts.sole
    expect(contract).to be_draft
    before = order.financial_summary.deep_dup
    contract_snapshot = contract.lifecycle_metadata.deep_dup
    patch "#{orders_url}/#{order.id}", params: { sales_order: { items: [{
      name: 'Synthetic attempted change', quantity: 1, unit_cents: 1, one_time_cents: 1
    }] } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('Condicoes aceitas/contratadas sao imutaveis')
    expect(order.reload.financial_summary).to eq(before)
    expect(contract.reload.lifecycle_metadata).to eq(contract_snapshot)
    expect(order.commissions.sole.base_cents).to eq(100_000)
  end
end
