require 'rails_helper'

RSpec.describe 'Broker connection summary reporting permissions', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:custom_role) { create(:custom_role, account: account, permissions: ['report_manage']) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_broker/inboxes/#{inbox.id}/summary" }

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('jrc_broker')
    account.account_users.find_by!(user: agent).update!(custom_role: custom_role)
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'honors reporting permission without granting configuration permission and honors its revocation' do
    create(:inbox_member, inbox: inbox, user: agent)
    ReportingEvent.create!(account: account, inbox: inbox, name: 'first_response', value: 120, created_at: 1.day.ago)

    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['metrics']).to include('avg_first_response_time' => 120.0, 'eligible_agents' => nil)
    expect(response.parsed_body).to include('policy' => nil, 'teams' => [])

    custom_role.update!(permissions: [])
    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['metrics']).to be_nil
  end

  it 'does not turn reporting permission into access to an unassigned connection' do
    get url, headers: agent.create_new_auth_token

    expect(response).to have_http_status(:forbidden)
  end
end
