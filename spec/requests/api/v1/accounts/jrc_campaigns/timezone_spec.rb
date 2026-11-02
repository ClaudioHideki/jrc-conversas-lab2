require 'rails_helper'

RSpec.describe 'Campaign timezone metadata', type: :request do
  let(:account) { create(:account, reporting_timezone: 'Brasilia') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_campaigns" }

  before { account.enable_features!('jrc_campaigns') }

  it 'exposes the current account timezone as IANA for automatic browser form defaults' do
    create(:account, reporting_timezone: 'Asia/Tokyo')
    get "#{base}/metadata", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['account_timezone']).to eq('America/Sao_Paulo')
  end

  [nil, false].each do |setting|
    it "allows the browser timezone when the account setting is #{setting.inspect}" do
      account.update!(reporting_timezone: setting)
      get "#{base}/metadata", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to have_key('account_timezone')
      expect(response.parsed_body['account_timezone']).to be_nil
    end
  end
end
