require 'rails_helper'

RSpec.describe 'Company Backoffice context API', :approval_core, :authority_core, type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:domain) { authority_domain(account, actor) }
  let(:url) { "/api/v1/accounts/#{account.id}/customers/companies/#{domain[:customer].id}/backoffice" }
  let(:headers) { actor.create_new_auth_token }

  before do
    raise 'Owned master context API database required' unless Rails.env.test? && ENV['POSTGRES_DATABASE'] == 'jrc_rel_v2_candidate_test'

    domain
    role = create(:custom_role, account: account, permissions: %w[jrc_crm contact_manage])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
  end

  it 'returns native scoped rows and safe cache headers while ignoring widening parameters' do
    get url, headers: headers, params: { company_id: 0, user_id: 0, account_id: 0, per_page: 500 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([domain[:operation].id])
    expect(response.parsed_body.fetch('company_id')).to eq(domain[:customer].id)
    expect(response.parsed_body.fetch('meta')).to include('total' => 1, 'per_page' => 50)
    expect(response.headers).to include('Cache-Control' => 'no-store', 'X-Content-Type-Options' => 'nosniff')
    expect(response.body).not_to include('metadata', 'description', 'personal_tax_identifier', 'encrypted_credentials')
  end

  it 'denies direct context access when CRM is disabled even though the master directory remains available' do
    account.disable_features!('jrc_crm')
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(domain[:operation].request_number)
  end

  it 'rejects foreign users and unsupported context views' do
    foreign = create(:user, account: create(:account), role: :administrator)
    get url, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get url, headers: headers, params: { view: 'arbitrary_private_document' }
    expect(response).to have_http_status(:bad_request)
  end
end
