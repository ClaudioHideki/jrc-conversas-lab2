require 'rails_helper'

RSpec.describe 'Commercial reconciliation with the official CRM', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm" }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: account, owner: agent, source_type: 'manual', status: 'approved',
                             products_cents: 10_000, total_cents: 10_000)
  end

  before { account.enable_features!('jrc_crm') }

  it 'allows an agent to operate own orders but not an administrator order' do
    get "#{url}/sales_orders/#{order.id}", headers: headers
    expect(response).to have_http_status(:ok)
    order.update!(owner: admin)
    get "#{url}/sales_orders/#{order.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'denies direct access to every new area when the CRM feature is off' do
    account.disable_features!('jrc_crm')
    %w[sales_orders contracts goals commissions backoffice_requests invoices payments contract_templates commission_programs].each do |area|
      get "#{url}/#{area}", headers: headers
      expect(response).to have_http_status(:forbidden), area
    end
  end

  it 'respects a CustomRole without CRM permission instead of treating it as a native agent' do
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    account.account_users.find_by!(user: agent).update!(custom_role: role)
    %w[sales_orders contracts goals commissions backoffice_requests invoices payments].each do |area|
      get "#{url}/#{area}", headers: headers
      expect(response).to have_http_status(:unauthorized), area
    end
  end

  it 'rejects another tenant product and rolls back the whole new order' do
    product = create(:jrc_crm_product, account: create(:account))
    expect do
      post "#{url}/sales_orders", headers: headers, as: :json,
           params: { sales_order: { items: [{ product_id: product.id, name: 'Foreign', quantity: 1, unit_cents: 100 }] } }
    end.not_to change(JrcCrm::SalesOrder, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not allow an agent to grant ownership of an order to another user' do
    patch "#{url}/sales_orders/#{order.id}", headers: headers, as: :json,
          params: { sales_order: { owner_id: admin.id } }
    expect(response).to have_http_status(:unauthorized)
    expect(order.reload.owner_id).to eq(agent.id)
  end

  it 'restricts goal and commission administration to administrators' do
    post "#{url}/goals", headers: headers, as: :json, params: { goal: { name: 'No grant' } }
    expect(response).to have_http_status(:unauthorized)
    post "#{url}/commissions", headers: headers, as: :json, params: { commission: { sales_order_id: order.id } }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lists goal scope choices only from the current Account and only to its administrator' do
    team = create(:team, account: account)
    unit = JrcCrm::BusinessUnit.create!(account: account, name: 'Comercial JRC', code: 'comercial')
    foreign = create(:account)
    create(:team, account: foreign)
    JrcCrm::BusinessUnit.create!(account: foreign, name: 'Outra empresa', code: 'outra')
    get "#{url}/goals/dashboard", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    options = response.parsed_body.fetch('scope_options')
    expect(options['teams'].pluck('id')).to eq([team.id])
    expect(options['business_units'].pluck('id')).to eq([unit.id])
    get "#{url}/goals/dashboard", headers: headers
    expect(response.parsed_body.fetch('scope_options')).to eq({})
  end

  it 'records a real payment even if the backoffice operational gate remains pending' do
    order.update!(snapshot: { send_to_implementation: true, checklist: [{ label: 'Ativar', done: false }] })
    JrcCrm::OrderWorkflowSyncService.new(order: order, actor: agent).call
    invoice = JrcCrm::Invoice.create!(account: account, sales_order: order, due_on: Date.current,
                                    subtotal_cents: 10_000, total_cents: 10_000, balance_cents: 10_000)
    post "#{url}/payments", headers: headers, as: :json,
         params: { payment: { invoice_id: invoice.id, amount_cents: 10_000, paid_at: Time.current } }
    expect(response).to have_http_status(:created)
    expect(invoice.reload).to be_paid
    request = order.backoffice_requests.sole
    expect(request).not_to be_completed
    expect(account.jrc_crm_audit_events.where(event_type: 'backoffice_payment_gate_pending', resource_id: request.id)).to exist
  end

  it 'keeps the current Flow stage-change callback when commercial associations are present' do
    pipeline = create(:jrc_crm_pipeline, account: account)
    first_stage = create(:jrc_crm_stage, account: account, pipeline: pipeline)
    deal = create(:jrc_crm_deal, account: account, owner: agent, pipeline: pipeline, stage: first_stage)
    conversation = create(:conversation, account: account)
    JrcCrm::DealConversation.create!(deal: deal, conversation: conversation, account: account)
    stage = create(:jrc_crm_stage, account: account, pipeline: deal.pipeline)
    allow(JrcFlows::DispatchJob).to receive(:perform_later)
    deal.update!(stage: stage)
    expect(JrcFlows::DispatchJob).to have_received(:perform_later).with(account.id, conversation.id, 'stage_changed', anything, nil, stage.id.to_s)
  end
end
