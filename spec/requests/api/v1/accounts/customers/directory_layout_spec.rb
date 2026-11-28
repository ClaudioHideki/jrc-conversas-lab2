require 'rails_helper'

RSpec.describe 'Customer directory layout data', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}" }

  before { account.enable_features!('jrc_customer_master') }

  it 'returns contact metrics and finds the authorized contact by company, owner and inbox' do
    travel_to(Time.zone.local(2026, 11, 28, 15, 0, 0)) do
      company = account.master_companies.create!(name: 'Árvore Teste', owner_id: actor.id)
      contact = create(:contact, account: account, company_id: company.id, email: 'linked@example.test', last_activity_at: Time.current)
      create(:contact, account: account, email: 'older@example.test', created_at: 40.days.ago, last_activity_at: 40.days.ago)
      inbox = create(:inbox, account: account)
      create(:contact_inbox, inbox: inbox, contact: contact)
      foreign_inbox = create(:inbox)

      get "#{base}/contacts/search", headers: headers, params: {
        q: 'Árvore', directory: true, directory_owner_id: actor.id, directory_inbox_id: inbox.id, include_contact_inboxes: false
      }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('meta', 'directory')).to eq('total' => 2, 'new_this_month' => 1, 'inactive' => 1, 'linked' => 1)
      expect(response.parsed_body.fetch('payload').sole).to include(
        'id' => contact.id, 'directory' => { 'inbox_ids' => [inbox.id], 'company_name' => company.name, 'owner_name' => actor.name,
                                             'next_action' => nil }
      )

      get "#{base}/contacts", headers: headers, params: { directory: true, directory_inbox_id: foreign_inbox.id }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('payload')).to be_empty

      get "#{base}/contacts", headers: headers
      expect(response.parsed_body.fetch('meta')).not_to have_key('directory')
    end
  end

  it 'sorts companies and filters unassigned records while retaining account summary counts' do
    account.master_companies.create!(name: 'Alpha', relationship_type: 'customer', owner_id: actor.id)
    account.master_companies.create!(name: 'Beta', relationship_type: 'customer', active: false)
    account.master_companies.create!(name: 'Zulu', relationship_type: 'prospect')
    create(:account).master_companies.create!(name: 'Foreign', relationship_type: 'prospect')

    get "#{base}/customers/companies", headers: headers, params: { directory: true, sort: '-name', owner_id: 'unassigned' }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('name')).to eq(%w[Zulu Beta])
    expect(response.parsed_body.dig('meta', 'directory')).to eq('total' => 3, 'customers' => 1, 'prospects' => 1, 'unassigned' => 2)
  end

  it 'confirms the current revision as administrator before deleting and preserves people' do
    company = account.master_companies.create!(name: 'Company to remove')
    contact = create(:contact, account: account, company_id: company.id, email: 'keep@example.test')
    url = "#{base}/customers/companies/#{company.id}"
    revision = company.reload.updated_at.iso8601(6)

    delete url, headers: headers, params: { revision: revision }, as: :json
    expect(response).to have_http_status(:bad_request)

    agent = create(:user, account: account, role: :agent)
    delete url, headers: agent.create_new_auth_token, params: { confirm: true, revision: revision }, as: :json
    expect(response).to have_http_status(:unauthorized)

    delete url, headers: headers, params: { confirm: true, revision: 1.minute.ago.iso8601(6) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(contact.reload.company_id).to eq(company.id)

    delete url, headers: headers, params: { confirm: true, revision: revision }, as: :json
    expect(response).to have_http_status(:no_content)
    expect(account.master_companies.exists?(company.id)).to be(false)
    expect(contact.reload.company_id).to be_nil
    expect(JrcCrm::AuditEvent.where(account_id: account.id, resource_id: company.id, event_type: 'customer_company_deleted')).to exist
  end

  it 'keeps the company and its contacts linked when a foreign key blocks deletion' do
    company = account.master_companies.create!(name: 'Head office')
    branch = account.master_companies.create!(name: 'Branch', parent_company: company)
    contact = create(:contact, account: account, company_id: company.id, email: 'linked@example.test')
    url = "#{base}/customers/companies/#{company.id}"

    delete url, headers: headers, params: { confirm: true, revision: company.reload.updated_at.iso8601(6) }, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('code' => 'COMPANY_IN_USE')
    expect(contact.reload.company_id).to eq(company.id)
    expect(branch.reload.parent_company_id).to eq(company.id)
  end
end
