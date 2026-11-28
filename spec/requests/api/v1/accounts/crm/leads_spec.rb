require 'rails_helper'

RSpec.describe 'CRM leads API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/leads" }

  before { account.enable_features!('jrc_crm') }

  it 'classifies a conversation as a lead idempotently' do
    headers = agent.create_new_auth_token

    post "#{base_url}/from_conversation", params: { conversation_id: conversation.id }, headers: headers, as: :json
    first_id = response.parsed_body.dig('lead', 'id')

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['created']).to be(true)
    expect(response.parsed_body.dig('lead', 'conversation_id')).to eq(conversation.id)

    post "#{base_url}/from_conversation", params: { conversation_id: conversation.id }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['created']).to be(false)
    expect(response.parsed_body.dig('lead', 'id')).to eq(first_id)
  end

  it 'does not classify a conversation from another account' do
    foreign_conversation = create(:conversation)

    post "#{base_url}/from_conversation",
         params: { conversation_id: foreign_conversation.id },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'changes the public status without reloading and records the audit event' do
    lead = JrcCrm::Lead.create!(account: account, owner: agent, name: 'Qualificação', status: 'in_contact')

    patch "#{base_url}/#{lead.id}", params: { lead: { status: 'qualified' } },
                                         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['status']).to eq('qualified')
    event = JrcCrm::AuditEvent.for_resource('JrcCrm::Lead', lead.id).recent.first
    expect(event.attributes.slice('from_value', 'to_value')).to eq('from_value' => 'in_contact', 'to_value' => 'qualified')
  end

  it 'converts a qualified lead once and returns the existing deal on a repeated request' do
    lead = JrcCrm::Lead.create!(account: account, owner: agent, name: 'Conversão', status: 'qualified')

    post "#{base_url}/#{lead.id}/convert", headers: agent.create_new_auth_token, as: :json
    first_deal_id = response.parsed_body.dig('deal', 'id')
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['created']).to be(true)

    post "#{base_url}/#{lead.id}/convert", headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['created']).to be(false)
    expect(response.parsed_body.dig('deal', 'id')).to eq(first_deal_id)
  end

  it 'creates a contact and preserves qualification and activities when turning the lead into a deal' do
    headers = agent.create_new_auth_token
    post base_url, params: {
      lead: {
        name: 'Mariana Teste', email: 'mariana@example.test', status: 'qualified', notes: 'Validar escopo',
        qualification: { product_interest: 'Atendimento', quantity: 10,
                         fields: [{ label: 'Unidade', value: 'Centro' }] }
      },
      next_activity: { title: 'Demonstrar solução', activity_type: 'demonstration', due_at: 2.days.from_now.iso8601 }
    }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    lead_id = response.parsed_body.fetch('id')
    contact_id = response.parsed_body.fetch('contact_id')
    expect(account.contacts.find(contact_id).email).to eq('mariana@example.test')

    post "#{base_url}/#{lead_id}/convert", params: {
      next_activity: { title: 'Preparar proposta', activity_type: 'proposal', due_at: 3.days.from_now.iso8601 }
    }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    deal_id = response.parsed_body.dig('deal', 'id')
    deal = account.jrc_crm_deals.find(deal_id)
    expect(deal.contact_id).to eq(contact_id)
    expect(deal.custom_attributes).to include('quantity' => 10, 'fields' => [{ 'label' => 'Unidade', 'value' => 'Centro' }])
    expect(deal.activities.pluck(:title)).to contain_exactly('Demonstrar solução', 'Preparar proposta')
    expect(deal.lead.activities.sole.deal_id).to eq(deal.id)

    get "/api/v1/accounts/#{account.id}/crm/deals/#{deal_id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['description']).to eq('Validar escopo')
    expect(response.parsed_body.fetch('history').pluck('event_type')).to include('lead_created', 'lead_converted')
  end

  it 'persists and returns contact, owner and stage throughout lead conversion' do
    contact = create(:contact, account: account, name: 'Cliente Teste 01')
    conversation = create(:conversation, account: account, contact: contact, assignee: agent)
    lead = JrcCrm::Lead.create!(account: account, owner: agent, contact: contact, conversation: conversation,
                               name: 'Cliente Teste 01', status: 'qualified')
    pipeline = JrcCrm::DefaultPipelineService.new(account).perform
    stage = pipeline.stages.active.order(:position).first

    post "#{base_url}/#{lead.id}/convert",
         params: { deal_title: 'Negócio - Cliente Teste 01', pipeline_id: pipeline.id,
                   stage_id: stage.id, value_cents: 150_000 },
         headers: agent.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:ok)
    deal = JrcCrm::Deal.find(response.parsed_body.dig('deal', 'id'))
    expect(deal.attributes.slice('contact_id', 'owner_id', 'stage_id')).to eq(
      'contact_id' => contact.id, 'owner_id' => agent.id, 'stage_id' => stage.id
    )
    expect(response.parsed_body.dig('deal', 'contact', 'name')).to eq('Cliente Teste 01')
    expect(response.parsed_body.dig('deal', 'owner', 'id')).to eq(agent.id)
    expect(response.parsed_body.dig('deal', 'stage', 'id')).to eq(stage.id)

    get "/api/v1/accounts/#{account.id}/crm/deals", headers: agent.create_new_auth_token, as: :json
    serialized_deal = response.parsed_body.find { |item| item['id'] == deal.id }
    expect(serialized_deal.dig('contact', 'name')).to eq('Cliente Teste 01')
    expect(serialized_deal.dig('owner', 'id')).to eq(agent.id)
    expect(serialized_deal.dig('stage', 'id')).to eq(stage.id)
  end
end
