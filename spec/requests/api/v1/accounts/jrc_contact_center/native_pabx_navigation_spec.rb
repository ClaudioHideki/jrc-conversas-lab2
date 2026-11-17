require 'rails_helper'

RSpec.describe 'Call Center reuses protected native PABX settings', type: :request do
  let(:account) { create(:account) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_administer]) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/administration" }

  before { account.enable_features!('jrc_contact_center', 'custom_roles') }

  it 'does not offer infrastructure settings to an account administrator' do
    actor = create(:user, :contact_center_eligible, account: account, role: :administrator)
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    get base, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('native_links', 'pabx_settings')).to be(false)
    get "/api/v1/accounts/#{account.id}/telephony_integration", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'offers only the existing settings route to an eligible native administrative SuperAdmin' do
    actor = create(:super_admin, name: 'SYNTHETIC PABX admin', email: "root-#{SecureRandom.hex(6)}@example.test")
    member = create(:account_user, account: account, user: actor, role: :administrator, custom_role: role)
    JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: true)
    get base, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('native_links', 'pabx_settings')).to be(true)
    get "/api/v1/accounts/#{account.id}/telephony_integration", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key('api_password')
  end
end
