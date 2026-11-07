require 'rails_helper'

RSpec.describe 'Native CRM lead deletion access', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:lead) { create(:jrc_crm_lead, account: account, owner: admin) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/leads/#{lead.id}" }

  before { account.enable_features!('jrc_crm') }

  it 'denies another account without deleting its lead or producing a deletion audit' do
    other_account = create(:account)
    other_account.enable_features!('jrc_crm')
    other_admin = create(:user, account: other_account, role: :administrator)

    delete "/api/v1/accounts/#{other_account.id}/crm/leads/#{lead.id}", headers: other_admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(lead.reload).to be_persisted
    expect(JrcCrm::AuditEvent.where(event_type: 'lead_deleted', resource_id: lead.id)).not_to exist
  end

  it 'does not let an ordinary CRM agent delete another owners lead' do
    agent = create(:user, account: account, role: :agent)

    delete url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(lead.reload.owner_id).to eq(admin.id)
    expect(JrcCrm::AuditEvent.where(event_type: 'lead_deleted', resource_id: lead.id)).not_to exist
  end

  it 'denies deletion when the native CRM feature is disabled' do
    lead
    account.disable_features!('jrc_crm')

    delete url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(lead.reload).to be_persisted
    expect(JrcCrm::AuditEvent.where(event_type: 'lead_deleted', resource_id: lead.id)).not_to exist
  end
end
