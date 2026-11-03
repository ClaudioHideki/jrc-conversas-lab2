require 'rails_helper'

RSpec.describe 'Canonical contact module records', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Empresa') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:root) { "/api/v1/accounts/#{account.id}/customers" }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:inbox_member) { create(:inbox_member, inbox: inbox, user: actor) }

  before { account.enable_features!('jrc_customer_master') }

  it 'uses the native inbox permission scope and ignores caller IDs that would widen the subject' do
    visible = create(:conversation, account: account, inbox: inbox, contact: contact,
                                    custom_attributes: { private_config: 'PRIVATE_CONFIGURATION' })
    create(:message, account: account, conversation: visible, private: true, content: 'PRIVATE_NOTE_CONTENT')
    hidden_inbox = create(:channel_api, account: account).inbox
    hidden = create(:conversation, account: account, inbox: hidden_inbox, contact: contact)
    other_contact = create(:contact, account: account)
    unrelated = create(:conversation, account: account, inbox: inbox, contact: other_contact)
    untrusted = { kind: 'conversations', contact_id: other_contact.id, user_id: 0, company_id: 0, unit_id: 0 }
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: untrusted
    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].pluck('id')).to eq([visible.id])
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    expect(response.body).not_to include('PRIVATE_CONFIGURATION', 'PRIVATE_NOTE_CONTENT', 'custom_attributes', 'content_attributes')
    expect(response.parsed_body['payload'].pluck('id')).not_to include(hidden.id, unrelated.id)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'revalidates an inbox membership withdrawal on the next call' do
    create(:conversation, account: account, inbox: inbox, contact: contact)
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'conversations' }
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    inbox_member.destroy!
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'conversations' }
    expect(response.parsed_body['payload']).to be_empty
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
  end

  it 'paginates the same authorized source without duplicates and preserves the company endpoint contract' do
    ids = Array.new(3) { create(:conversation, account: account, inbox: inbox, contact: contact).id }
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'conversations', per_page: 2, page: 1 }
    first = response.parsed_body
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'conversations', per_page: 2, page: 2 }
    second = response.parsed_body
    expect(first['meta']).to include('total' => 3, 'page' => 1, 'per_page' => 2)
    expect([first['payload'].length, second['payload'].length]).to eq([2, 1])
    expect(first['payload'].pluck('id') & second['payload'].pluck('id')).to be_empty
    expect(first['payload'].pluck('id') + second['payload'].pluck('id')).to eq(ids.reverse)
    get "#{root}/companies/#{company.id}/records", headers: headers, params: { kind: 'conversations', per_page: 2, page: 1 }
    expect(response.parsed_body).to eq(first)
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'conversations', per_page: 500, page: 0 }
    expect(response.parsed_body['meta']).to include('per_page' => 50, 'page' => 1)
  end

  it 'rejects foreign subjects and foreign actors rather than trusting supplied IDs' do
    foreign = create(:account)
    foreign_contact = create(:contact, account: foreign)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    get "#{root}/contacts/#{foreign_contact.id}/records", headers: headers, params: { kind: 'conversations' }
    expect(response).to have_http_status(:not_found)
    get "#{root}/contacts/#{contact.id}/records", headers: foreign_actor.create_new_auth_token,
                                                  params: { kind: 'conversations', account_id: foreign.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires the directory permission and rejects unavailable or unknown modules' do
    get "#{root}/contacts/#{contact.id}/records", params: { kind: 'conversations' }
    expect(response).to have_http_status(:unauthorized)
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'contracts' }
    expect(response).to have_http_status(:bad_request)
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'untrusted_models' }
    expect(response).to have_http_status(:bad_request)
    account.disable_features!('jrc_customer_master')
    get "#{root}/contacts/#{contact.id}/records", headers: headers, params: { kind: 'conversations' }
    expect(response).to have_http_status(:unauthorized)
  end
end
