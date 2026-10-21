# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JRC Contact Center context', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_contact_center/context" }

  it 'is unavailable while the account feature is disabled' do
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'exposes only the F0 capability contract when the feature is enabled' do
    account.enable_features!('jrc_contact_center')
    get url, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('contract_version' => 1, 'account_id' => account.id.to_s, 'feature' => 'jrc_contact_center')
    expect(response.parsed_body.dig('provider', 'key')).to eq('jrc_pabx')
    expect(response.parsed_body.dig('provider', 'capabilities', 'external_api')).to eq('pending_contract')
    expect(response.parsed_body['counts']).to include('units' => 0, 'queues' => 0, 'active_calls' => 0)
  end
end
