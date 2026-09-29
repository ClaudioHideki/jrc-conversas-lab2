require 'rails_helper'

# Native regression gate: requires the consolidated migrations in PostgreSQL.
# These examples were written, not executed in the source-only integration lab.
RSpec.describe 'Consolidated commercial protections', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:contact) { create(:contact, account: account) }
  let(:pipeline) { create(:jrc_crm_pipeline, account: account) }
  let(:stage) { create(:jrc_crm_stage, account: account, pipeline: pipeline) }
  let(:deal) { create(:jrc_crm_deal, account: account, owner: admin, pipeline: pipeline, stage: stage, contact: contact) }
  let(:proposal) do
    create(:jrc_crm_proposal, account: account, owner: admin, deal: deal, status: 'accepted',
      accepted_at: Time.current, implementation_cents: 100_000, monthly_cents: 2000,
      shipping_mode: 'separate', shipping_cents: 5001, shipping_in_installments: false,
      payment_condition: 'down_payment_installments', payment_method: 'boleto',
      down_payment_cents: 30_000, installments_count: 7)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm" }
  before { account.enable_features!('jrc_crm') }

  def create_order_from_proposal(nested: false)
    payload = nested ? { sales_order: { proposal_id: proposal.id, total_cents: 1, down_payment_cents: 0,
      items: [{ name: 'Untrusted input', quantity: 1, unit_cents: 1 }] } } : { proposal_id: proposal.id }
    post "#{url}/sales_orders", params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    JrcCrm::SalesOrder.find(response.parsed_body.fetch('id'))
  end

  it 'keeps canonical financials in top-level and wizard conversion without duplicate orders' do
    order = create_order_from_proposal
    same = create_order_from_proposal(nested: true)
    expect(same.id).to eq(order.id)
    expect(proposal.sales_orders.count).to eq(1)
    expect(JrcCrm::OrderFinancials.same_terms?(proposal.financial_summary, same.financial_summary)).to be(true)
  end

  it 'uses the same conversion for the proposal member action' do
    order = create_order_from_proposal
    post "#{url}/proposals/#{proposal.id}/convert_to_order", headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['id']).to eq(order.id)
  end

  it 'ignores client monetary overrides even on the first wizard conversion' do
    order = create_order_from_proposal(nested: true)
    expect(order.total_cents).to eq(proposal.financial_summary[:total_cents])
    expect(order.down_payment_cents).to eq(30_000)
    expect(order.order_items.pluck(:name)).not_to include('Untrusted input')
  end

  it 'rejects conversion before acceptance' do
    proposal.update!(status: 'draft', accepted_at: nil)
    expect { JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: admin).call }.to raise_error(ArgumentError)
    expect(proposal.sales_orders.count).to eq(0)
  end

  it 'does not expose another account proposal through conversion' do
    other = create(:account)
    user = create(:user, account: other, role: :administrator)
    other.enable_features!('jrc_crm')
    post "/api/v1/accounts/#{other.id}/crm/sales_orders", params: { proposal_id: proposal.id }, headers: user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects financial edits of an accepted source order' do
    order = create_order_from_proposal
    patch "#{url}/sales_orders/#{order.id}", params: { sales_order: { down_payment_cents: 1 } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.reload.down_payment_cents).to eq(30_000)
  end

  it 'keeps the order financial snapshot in a contract despite contradictory payload values' do
    order = create_order_from_proposal
    post "#{url}/contracts", params: { contract: { sales_order_id: order.id, status: 'draft',
      one_time_cents: 1, monthly_cents: 1, payment_condition: 'cash' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    contract = JrcCrm::Contract.find(response.parsed_body.fetch('id'))
    expect(contract.financial_summary.to_h).to eq(order.financial_summary.except(:items).deep_stringify_keys)
    expect(contract.one_time_cents).to eq(order.total_cents)
    expect(contract.contract_items.count).to eq(order.order_items.count)
    patch "#{url}/contracts/#{contract.id}", params: { contract: { monthly_cents: 1 } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.monthly_cents).to eq(order.monthly_cents)
  end

  it 'preserves activities when deleting an unconverted lead' do
    lead = create(:jrc_crm_lead, account: account, owner: admin, contact: contact)
    activity = create(:jrc_crm_activity, account: account, user: admin, deal: nil, lead: lead, contact: contact)
    delete "#{url}/leads/#{lead.id}", headers: headers, as: :json
    expect(response).to have_http_status(:no_content)
    expect(activity.reload.lead_id).to be_nil
    expect(activity.contact_id).to eq(contact.id)
    expect(JrcCrm::AuditEvent.where(account_id: account.id, event_type: 'lead_deleted', resource_id: lead.id)).to exist
  end

  it 'blocks deletion of a lead linked to a deal' do
    lead = create(:jrc_crm_lead, account: account, owner: admin)
    deal.update!(lead: lead)
    delete "#{url}/leads/#{lead.id}", headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(lead.reload).to be_persisted
  end

  it 'includes direct orders and contracts in Customer 360' do
    post "#{url}/sales_orders", params: { sales_order: { contact_id: contact.id, status: 'draft',
      items: [{ name: 'Direct', quantity: 1, unit_cents: 10_000 }] } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.fetch('id')
    post "#{url}/contracts", params: { contract: { sales_order_id: order_id, status: 'draft' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    get "#{url}/customers/#{contact.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('metrics', 'orders')).to eq(1)
    expect(response.parsed_body.dig('metrics', 'contracts')).to eq(1)
    expect(response.parsed_body['orders'].first['id']).to eq(order_id)
  end
  it 'preserves the published schedule when last sent timestamp changes' do
    proposal.events.create!(account: account, event_type: 'sent', description: 'Proposta enviada', metadata: { financial_anchor_on: '2026-09-01' })
    expected = proposal.financial_summary[:first_due_date]
    proposal.update!(sent_at: Time.current + 60.days)
    expect(proposal.reload.financial_summary[:first_due_date]).to eq(expected)
  end

end
