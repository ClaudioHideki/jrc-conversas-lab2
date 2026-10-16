require 'rails_helper'

RSpec.describe 'Customer relationship map', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Synthetic customer') }
  let(:path) { "/api/v1/accounts/#{account.id}/customers/companies/#{company.id}/relationships" }

  before { account.enable_features!('jrc_customer_master') }

  it 'returns the authorized customer projection without customer message content' do
    contact = create(:contact, account: account, company_id: company.id)
    conversation = create(:conversation, account: account, contact: contact)
    create(:message, account: account, conversation: conversation, content: 'MESSAGE_BODY_CANARY', private: false)
    get path, headers: user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('version' => 1, 'root' => { 'key' => "company:#{company.id}" })
    expect(response.body).not_to include('MESSAGE_BODY_CANARY', 'phone_number', 'content_attributes')
  end

  it 'does not allow a company from another account to be selected by numeric ID' do
    foreign = create(:account).master_companies.create!(name: 'FOREIGN_CUSTOMER_CANARY')
    get "/api/v1/accounts/#{account.id}/customers/companies/#{foreign.id}/relationships", headers: user.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('FOREIGN_CUSTOMER_CANARY')
  end

  it 'requires the existing customer directory capability' do
    account.disable_features!('jrc_customer_master')
    get path, headers: user.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end
end
