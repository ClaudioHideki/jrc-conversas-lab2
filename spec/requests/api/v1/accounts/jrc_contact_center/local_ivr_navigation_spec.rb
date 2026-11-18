require 'rails_helper'

RSpec.describe 'Local IVR navigation uses its native configuration authority', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:headers) { user.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }

  before { account.enable_features!('jrc_contact_center', 'custom_roles') }

  def set_role(*permissions)
    role = create(:custom_role, account: account, permissions: ['jrc_contact_center_view', *permissions])
    member.update!(custom_role: role)
  end

  it 'offers the existing local editor to a configurer without granting provider publication' do
    set_role('jrc_contact_center_configure')
    get "#{base}/administration", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('cards').pluck('key')).to include('ivr')
    expect(response.parsed_body.fetch('capabilities')).to include('configure' => true, 'publish' => false)
    get "#{base}/administration/ivr", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{base}/ivr_drafts", headers: headers
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'preserves the publisher entry without granting local draft configuration' do
    set_role('jrc_contact_center_publish')
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('cards').pluck('key')).to include('ivr')
    expect(response.parsed_body.fetch('capabilities')).to include('configure' => false, 'publish' => true)
    get "#{base}/administration/ivr", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{base}/ivr_drafts", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
  end

  it 'does not expose the entry or either endpoint to a viewer without configuration or publication' do
    set_role
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('cards').pluck('key')).not_to include('ivr')
    get "#{base}/administration/ivr", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/ivr_drafts", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'uses current inherited configuration and withdraws discovery after native team removal' do
    set_role
    team = create(:team, account: account)
    team.add_members([user.id])
    JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: ['jrc_contact_center_configure'])
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('cards').pluck('key')).to include('ivr')
    get "#{base}/ivr_drafts", headers: headers
    expect(response).to have_http_status(:ok)
    team.remove_members([user.id])
    get "#{base}/administration", headers: headers
    expect(response.parsed_body.fetch('cards').pluck('key')).not_to include('ivr')
    get "#{base}/ivr_drafts", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::QueueMembership.where(account_user: member)).to be_empty
    expect(account.jrc_crm_user_business_units.where(user: user)).to be_empty
  end

  it 'never treats discoverability as eligibility after access is revoked' do
    set_role('jrc_contact_center_configure')
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    get "#{base}/administration", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/ivr_drafts", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end
end
