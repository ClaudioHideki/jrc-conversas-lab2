require 'rails_helper'

RSpec.describe 'CRM contact to lead', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, name: 'Cliente JRC', email: 'cliente@example.test') }
  let(:headers) { agent.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/leads" }

  before do
    account.enable_features!('jrc_crm')
    account.account_users.find_by!(user: agent).update!(crm_enabled: true)
  end

  it 'reads without creating, creates once and reuses the existing lead on retry' do
    get "#{url}/for_contact", params: { contact_id: contact.id }, headers: headers
    expect(response.parsed_body['lead']).to be_nil

    expect do
      2.times { post "#{url}/from_contact", params: { contact_id: contact.id }, headers: headers, as: :json }
    end.to change(JrcCrm::Lead, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['created']).to be(false)
    lead = account.jrc_crm_leads.find(response.parsed_body.dig('lead', 'id'))
    expect(lead.attributes.slice('owner_id', 'contact_id', 'idempotency_key')).to eq(
      'owner_id' => agent.id, 'contact_id' => contact.id, 'idempotency_key' => "contact:#{contact.id}"
    )
    expect(contact.reload.name).to eq('Cliente JRC')
    expect(account.jrc_crm_audit_events.where(resource_id: lead.id, event_type: 'lead_created').count).to eq(1)
  end

  it 'reuses a visible legacy lead without overwriting its status or owner' do
    lead = account.jrc_crm_leads.create!(owner: agent, contact: contact, name: 'Existente', status: 'qualified')
    expect do
      post "#{url}/from_contact", params: { contact_id: contact.id, owner_id: 999, status: 'new' }, headers: headers, as: :json
    end.not_to change(JrcCrm::Lead, :count)
    expect(response.parsed_body.dig('lead', 'id')).to eq(lead.id)
    expect(lead.reload.status).to eq('qualified')
  end

  it 'denies both endpoints when the individual CRM permission is disabled' do
    account.account_users.find_by!(user: agent).update!(crm_enabled: false)
    get "#{url}/for_contact", params: { contact_id: contact.id }, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect do
      post "#{url}/from_contact", params: { contact_id: contact.id }, headers: headers, as: :json
    end.not_to change(JrcCrm::Lead, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'denies access when CRM is disabled for the account' do
    account.disable_features!('jrc_crm')
    post "#{url}/from_contact", params: { contact_id: contact.id }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not create or disclose a lead for a contact from another account' do
    foreign_contact = create(:contact)
    post "#{url}/from_contact", params: { contact_id: foreign_contact.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(account.jrc_crm_leads).to be_empty
  end

  it 'does not disclose or duplicate a lead owned by another agent' do
    other = create(:user, account: account, role: :agent)
    lead = account.jrc_crm_leads.create!(owner: other, contact: contact, name: 'Restrito')
    expect do
      post "#{url}/from_contact", params: { contact_id: contact.id }, headers: headers, as: :json
    end.not_to change(JrcCrm::Lead, :count)
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('lead')
    expect(lead.reload.owner).to eq(other)
  end

  it 'reports ambiguous legacy links without choosing or creating a record' do
    2.times { account.jrc_crm_leads.create!(owner: agent, contact: contact, name: 'Legado') }
    expect do
      post "#{url}/from_contact", params: { contact_id: contact.id }, headers: headers, as: :json
    end.not_to change(JrcCrm::Lead, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('CONTACT_HAS_MULTIPLE_LEADS')
  end

  it 'allows administrators without the agent-specific toggle' do
    account.account_users.find_by!(user: agent).update!(role: :administrator, crm_enabled: false)
    post "#{url}/from_contact", params: { contact_id: contact.id }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end
end
