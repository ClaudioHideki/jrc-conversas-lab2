require 'rails_helper'

RSpec.describe 'Versioned native priority signal configuration', type: :request do
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:headers) { manager.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/configuration" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship') }

  it 'persists opt-in fractional signal weights and retains original versions and stale-write rejection' do
    get url, headers: headers, as: :json
    original = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    expect(original['rules']).to include('priority_trend' => 0, 'priority_sla' => 0)
    change = original.deep_dup
    change['rules'].merge!('priority_trend' => 0.25, 'priority_sla' => 0.5)
    patch url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['history'].map { |row| row.dig('rules', 'priority_trend') }).to eq([0.25, 0])
    patch url, headers: headers, as: :json, params: original
    expect(response).to have_http_status(:conflict)
    expect(JrcRelationship::Configuration.find_by!(account: account).effective_rules['priority_sla']).to eq(0.5)
  end

  it 'rejects invalid weights and denies ordinary analysts and foreign accounts without a configuration write' do
    get url, headers: headers, as: :json
    change = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    change['rules']['priority_trend'] = -0.1
    patch url, headers: headers, as: :json, params: change
    expect(response).to have_http_status(:unprocessable_entity)
    analyst = create(:user, account: account, role: :agent)
    patch url, headers: analyst.create_new_auth_token, as: :json, params: change
    expect(response).to have_http_status(:forbidden)
    foreign = create(:account)
    patch "/api/v1/accounts/#{foreign.id}/relationship/configuration", headers: headers, as: :json, params: change
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::Configuration.where(account_id: [account.id, foreign.id])).to be_empty
  end
end
