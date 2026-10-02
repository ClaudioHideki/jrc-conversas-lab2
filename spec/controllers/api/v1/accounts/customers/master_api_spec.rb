require 'rails_helper'

RSpec.describe 'Customer master API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/customers" }
  before { account.enable_features!('jrc_customer_master') }

  it 'requires authentication' do
    get "#{root}/companies"
    expect(response).to have_http_status(:unauthorized)
  end
  it 'is opt-in for the account' do
    account.disable_features!('jrc_customer_master')
    get "#{root}/companies", headers: headers
    expect(response).to have_http_status(:forbidden)
  end
  it 'does not list companies of another account' do
    own = account.master_companies.create!(name: 'Own')
    other = create(:account).master_companies.create!(name: 'Private')
    get "#{root}/companies", headers: headers
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('id')).to include(own.id)
    expect(response.parsed_body['payload'].pluck('id')).not_to include(other.id)
  end
  it 'does not show a company addressed by an ID from another tenant' do
    foreign = create(:account).master_companies.create!(name: 'Private')
    get "#{root}/companies/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
  it 'creates a prospect without promoting it to customer' do
    post "#{root}/companies", headers: headers, params: { company: { name: 'Prospect', relationship_type: 'prospect' } }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('payload', 'relationship_type')).to eq('prospect')
  end
  it 'requires revision on a master company update' do
    own = account.master_companies.create!(name: 'Own')
    patch "#{root}/companies/#{own.id}", headers: headers, params: { company: { name: 'Overwrite' } }, as: :json
    expect(response).to have_http_status(:bad_request)
    expect(own.reload.name).to eq('Own')
  end
  it 'rejects a cross-account contact-company assignment' do
    foreign = create(:account).master_companies.create!(name: 'Private')
    post "#{root}/contacts", headers: headers, params: { contact: { name: 'Cross', company_id: foreign.id } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
  it 'restricts merges to administrators' do
    agent = create(:user, account: account)
    base = create(:contact, account: account)
    source = create(:contact, account: account)
    post "#{root}/contacts/#{base.id}/merge", headers: agent.create_new_auth_token,
         params: { source_contact_id: source.id, confirm: true }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(source.reload).to be_persisted
  end
  it 'refuses merging without explicit confirmation' do
    base = create(:contact, account: account)
    source = create(:contact, account: account)
    post "#{root}/contacts/#{base.id}/merge", headers: headers, params: { source_contact_id: source.id }, as: :json
    expect(response).to have_http_status(:bad_request)
  end
end
