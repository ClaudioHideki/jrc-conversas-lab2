require 'rails_helper'

RSpec.describe 'Sales order client/deal/proposal integrity', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:pipeline) { create(:jrc_crm_pipeline, account: account) }
  let(:stage) { create(:jrc_crm_stage, account: account, pipeline: pipeline) }
  let(:contact) { create(:contact, account: account, name: 'Marcelo Andrade', email: 'marcelo@nexora.test') }
  let(:other_contact) { create(:contact, account: account, name: 'Outro Cliente', email: 'outro@cliente.test') }
  let(:deal) { create(:jrc_crm_deal, account: account, owner: admin, pipeline: pipeline, stage: stage, contact: contact, title: 'Nexora - JRC Conversas') }
  let(:other_deal) { create(:jrc_crm_deal, account: account, owner: admin, pipeline: pipeline, stage: stage, contact: other_contact, title: 'Outro negocio') }
  let(:proposal) do
    create(:jrc_crm_proposal, account: account, owner: admin, deal: deal, status: 'sent', sent_at: Time.current,
      version_number: 3, implementation_cents: 120_000, monthly_cents: 100_000).tap do |record|
      record.update!(status: 'accepted', accepted_at: Time.current)
    end
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm" }

  before { account.enable_features!('jrc_crm') }

  it 'does not preload the customer base when selection opens without a query' do
    get "#{url}/sales_orders/selection_options", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('contacts')).to eq([])
  end

  it 'filters deals by the selected customer and does not expose another customer deal' do
    deal
    other_deal
    get "#{url}/sales_orders/selection_options", params: { contact_id: contact.id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body.fetch('deals').pluck('id')
    expect(ids).to include(deal.id)
    expect(ids).not_to include(other_deal.id)
  end

  it 'offers only accepted proposals and explains when a deal has proposals waiting for acceptance' do
    create(:jrc_crm_proposal, account: account, owner: admin, deal: deal, status: 'sent')
    proposal
    get "#{url}/sales_orders/selection_options", params: { deal_id: deal.id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('proposals').pluck('id')).to eq([proposal.id])
    expect(response.parsed_body.dig('proposal_state', 'counts', 'sent')).to eq(1)
  end

  it 'blocks a proposal submitted with a different deal/client even when the ids are valid in the same account' do
    post "#{url}/sales_orders", headers: headers, as: :json, params: {
      sales_order: { proposal_id: proposal.id, deal_id: other_deal.id, contact_id: other_contact.id, status: 'pending' }
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('errors').join(' ')).to match(/proposta nao pertence ao negocio/i)
  end

  it 'blocks a direct deal order whose customer is not linked to that deal' do
    post "#{url}/sales_orders", headers: headers, as: :json, params: {
      sales_order: {
        contact_id: other_contact.id, deal_id: deal.id, order_origin: 'proposal_deal', status: 'draft',
        items: [{ name: 'JRC Conversas', quantity: 1, unit_cents: 100_000 }]
      }
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('errors').join(' ')).to match(/mesmo cliente/i)
  end

  it 'requires a client for a direct order and audits an authorized exceptional order without proposal' do
    post "#{url}/sales_orders", headers: headers, as: :json, params: {
      sales_order: { order_origin: 'direct_sale', status: 'draft', items: [{ name: 'JRC Conversas', quantity: 1, unit_cents: 100_000 }] }
    }
    expect(response).to have_http_status(:unprocessable_entity)

    post "#{url}/sales_orders", headers: headers, as: :json, params: {
      sales_order: { contact_id: contact.id, order_origin: 'direct_sale', status: 'draft', items: [{ name: 'JRC Conversas', quantity: 1, unit_cents: 100_000 }] }
    }
    expect(response).to have_http_status(:created)
    order = JrcCrm::SalesOrder.find(response.parsed_body.fetch('id'))
    expect(order.order_origin).to eq('direct_sale')
    expect(order.created_by_id).to eq(admin.id)
    expect(account.jrc_crm_audit_events.where(event_type: 'order_created_without_proposal', resource_id: order.id)).to exist
  end

  it 'does not allow removing the required customer from an existing direct order' do
    post "#{url}/sales_orders", headers: headers, as: :json, params: {
      sales_order: { contact_id: contact.id, order_origin: 'direct_sale', status: 'draft', items: [{ name: 'JRC Conversas', quantity: 1, unit_cents: 100_000 }] }
    }
    expect(response).to have_http_status(:created)
    order = JrcCrm::SalesOrder.find(response.parsed_body.fetch('id'))

    [nil, ''].each do |empty_contact|
      patch "#{url}/sales_orders/#{order.id}", headers: headers, as: :json, params: { sales_order: { contact_id: empty_contact } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('errors').join(' ')).to match(/cliente e obrigatorio/i)
      expect(order.reload.contact_id).to eq(contact.id)
    end
  end

  it 'persists accepted proposal version, creator and full canonical linkage' do
    post "#{url}/sales_orders", headers: headers, as: :json, params: {
      sales_order: { proposal_id: proposal.id, deal_id: deal.id, contact_id: contact.id, status: 'pending' }
    }
    expect(response).to have_http_status(:created)
    order = JrcCrm::SalesOrder.find(response.parsed_body.fetch('id'))
    expect(order.deal_id).to eq(deal.id)
    expect(order.contact_id).to eq(contact.id)
    expect(order.proposal_id).to eq(proposal.id)
    expect(order.proposal_version).to eq(3)
    expect(order.order_origin).to eq('proposal_deal')
    expect(order.created_by_id).to eq(admin.id)
    expect(account.jrc_crm_audit_events.where(event_type: 'order_created', resource_id: order.id)).to exist
  end
end
