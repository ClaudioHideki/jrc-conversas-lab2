require 'rails_helper'

RSpec.describe 'Versioned native sentiment evidence configuration', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:headers) { manager.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/configuration" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'persists the configured window, preserves native history and rejects stale writes' do
    get url, headers: headers, as: :json
    original = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    expect(original['rules']['sentiment_window_days']).to eq(90)
    change = original.deep_dup
    change['rules']['sentiment_window_days'] = 14
    patch url, headers: headers, params: change, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['history'].map { |row| row.dig('rules', 'sentiment_window_days') }).to eq([14, 90])
    patch url, headers: headers, params: original, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcRelationship::Configuration.find_by!(account: account).effective_rules['sentiment_window_days']).to eq(14)
  end

  it 'refuses invalid evidence windows without committing a configuration or a version' do
    patch url, headers: headers, params: { scope_key: 'account', version: 1, rules: { sentiment_window_days: 0.5 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::Configuration.where(account: account)).to be_empty
    expect(JrcRelationship::ConfigurationVersion.where(account: account)).to be_empty
  end

  it 'denies a foreign account and ordinary analyst before configuration persistence' do
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship')
    path = "/api/v1/accounts/#{foreign.id}/relationship/configuration"
    patch path, headers: headers,
                params: { scope_key: 'account', version: 1, rules: { sentiment_window_days: 14 } }, as: :json
    expect(response).to have_http_status(:forbidden)
    account.account_users.find_by!(user: manager).update!(role: :agent)
    patch url, headers: headers, params: { scope_key: 'account', version: 1, rules: { sentiment_window_days: 14 } }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::Configuration.where(account_id: [account.id, foreign.id])).to be_empty
  end
end
