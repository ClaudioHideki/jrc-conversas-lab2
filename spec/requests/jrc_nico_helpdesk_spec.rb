require 'rails_helper'

RSpec.describe 'NICO HelpDesk configuration and preview', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_nico/helpdesk" }
  let(:headers) { User.find(sd_user.id).create_new_auth_token }
  let(:definition) { JrcNico::Helpdesk::Definition.defaults }
  let(:policy) { JrcNico::Helpdesk::Policies.new(sd_account_user).create(definition: definition) }

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
  end

  it 'provides authorized native choices and an OFF policy with no activation route' do
    get base, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => sd_account.id, 'activation_available' => false, 'can_manage' => true)
    expect(response.parsed_body.dig('options', 'units').pluck('id')).to include(sd_unit.id)
    post "#{base}/policies", params: { definition: definition }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    value = response.parsed_body
    post "#{base}/policies/#{value['id']}/publish", params: { digest: value['digest'] }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'published', 'enabled' => false)
  end

  it 'denies non-administrative writes while retaining native read scope' do
    agent = create(:user, account: sd_account, role: :agent)
    native_member = sd_account.account_users.find_by!(user_id: agent.id)
    create(:jrc_sd_membership, unit: sd_unit, account_user: native_member)
    agent_headers = agent.create_new_auth_token
    get base, headers: agent_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['can_manage']).to be(false)
    post "#{base}/policies", params: { definition: definition }, headers: agent_headers, as: :json
    # The inherited RequestExceptionHandler maps denied Pundit actions to 401.
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
    expect(JrcNico::Helpdesk::PolicyVersion.where(account: sd_account)).to be_empty
  end

  it 'returns sanitized invalid input and no key data in policy responses' do
    post "#{base}/policies", params: { definition: definition.merge('api_key' => 'test-only-secret-placeholder') }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'HELPDESK_INVALID_REQUEST')
    expect(response.body).not_to include('test-only-secret-placeholder')
  end

  it 'previews reports and seven KPIs without creating delivery or operational data' do
    value = policy
    expect { get "#{base}/report", params: { policy_id: value.id }, headers: headers }.not_to change(JrcNico::Helpdesk::DailyReport, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('preview' => true, 'persisted' => false)
    get "#{base}/kpis", params: { policy_id: value.id, from: 1.day.ago.iso8601 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['metrics'].size).to eq(7)
  end

  it 'audits disable without activation and rejects foreign account access' do
    value = policy
    post "#{base}/policies/#{value.id}/disable", params: { reason: 'Synthetic administrative stop', request_key: SecureRandom.uuid },
                                                 headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['action']).to eq('disable')
    expect(value.reload.enabled?).to be(false)
    foreign = create(:user, account: sd_foreign_account, role: :administrator)
    get base, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end
end
