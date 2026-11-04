require 'rails_helper'

RSpec.describe 'Versioned relationship health stability configuration', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:headers) { manager.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/configuration" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'persists the opt-in margin through the native endpoint and preserves the old version and stale-write guard' do
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    original = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    expect(original.dig('rules', 'health_hysteresis_points')).to eq(0)
    change = original.merge('rules' => original['rules'].merge('health_hysteresis_points' => 5))
    patch url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('rules', 'health_hysteresis_points')).to eq(5)
    expect(response.parsed_body['history'].map { |row| row.dig('rules', 'health_hysteresis_points') }).to eq([5, 0])
    patch url, headers: headers, as: :json, params: original
    expect(response).to have_http_status(:conflict)
    get url, headers: headers, as: :json
    expect(response.parsed_body.dig('rules', 'health_hysteresis_points')).to eq(5)
  end

  it 'rejects a margin that prevents full recovery without saving a configuration' do
    get url, headers: headers, as: :json
    change = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    change['rules']['health_hysteresis_points'] = 21
    patch url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::Configuration.where(account: account)).to be_empty
  end

  it 'denies ordinary analysts and foreign accounts through the existing configuration permission' do
    analyst = create(:user, account: account, role: :agent)
    get url, headers: analyst.create_new_auth_token, as: :json
    expect(response).to have_http_status(:forbidden)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/configuration", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::Configuration.where(account: foreign)).to be_empty
  end
end
