require 'rails_helper'

RSpec.describe 'Account human assignment policy', type: :request do
  let(:account) { create(:account, custom_attributes: { 'retained_setting' => true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_broker/assignment_policy" }

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }
  before { account.enable_features!('jrc_broker') }

  it 'lets an administrator save account-wide capacity without changing unrelated settings or activating a bot' do
    put url, headers: admin.create_new_auth_token, params: { enabled: true, max_open: 6, inbox_ids: [inbox.id] }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('enabled' => true, 'max_open' => 6, 'inbox_ids' => [inbox.id])
    expect(account.reload.custom_attributes['retained_setting']).to eq(true)
    expect(account.custom_attributes['nico_enabled']).to be_nil
  end

  it 'denies agents and administrators from another account' do
    [agent, create(:user, account: create(:account), role: :administrator)].each do |user|
      put url, headers: user.create_new_auth_token, params: { enabled: true, max_open: 6, inbox_ids: [inbox.id] }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
    expect(account.reload.custom_attributes['jrc_human_assignment']).to be_nil
  end

  it 'rejects an invalid limit without changing the policy' do
    put url, headers: admin.create_new_auth_token, params: { enabled: true, max_open: 0, inbox_ids: [inbox.id] }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.custom_attributes['jrc_human_assignment']).to be_nil
  end

  it 'requires an explicit same-account inbox selection before enabling distribution' do
    foreign = create(:inbox, account: create(:account))
    [[], [foreign.id], [inbox.id, inbox.id], [inbox.id.to_s]].each do |ids|
      put url, headers: admin.create_new_auth_token, params: { enabled: true, max_open: 6, inbox_ids: ids }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(account.reload.custom_attributes['jrc_human_assignment']).to be_nil
  end

  it 'starts disabled with no selected inbox and allows clearing the selection when disabling' do
    get url, headers: admin.create_new_auth_token
    expect(response.parsed_body).to eq('enabled' => false, 'max_open' => 10, 'inbox_ids' => [])
    put url, headers: admin.create_new_auth_token, params: { enabled: false, max_open: 6, inbox_ids: [] }, as: :json
    expect(response).to have_http_status(:ok)
  end
end
