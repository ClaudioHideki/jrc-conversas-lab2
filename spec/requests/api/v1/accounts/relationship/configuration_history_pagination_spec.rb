require 'rails_helper'

RSpec.describe 'Native configuration version pagination', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/configuration" }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, scope_key: 'account', version: 76) }
  let(:history) do
    Array.new(76) do |index|
      configuration.versions.create!(account: account, actor: actor, version: index + 1,
                                     weights: configuration.effective_weights, rules: configuration.effective_rules)
    end
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'pages all immutable versions without replacing the legacy recent-fifty or exact-source contracts' do
    originals = history.map(&:attributes)
    get url, headers: headers, params: { history_page: 3, history_per_page: 25 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('history').pluck('version')).to eq(26.downto(2).to_a)
    expect(response.parsed_body.fetch('history_meta')).to eq('page' => 3, 'per_page' => 25, 'total' => 76)
    expect(response.headers['Cache-Control']).to include('no-store')
    get url, headers: headers, params: { history_page: 4, history_per_page: 25 }
    expect(response.parsed_body.fetch('history').pluck('version')).to eq([1])
    expect(configuration.versions.order(:version).map(&:attributes)).to eq(originals)
  end

  it 'retains current native scope and configure denial for paged versions' do
    history
    foreign = create(:account)
    company = create(:company, account: foreign)
    get url, headers: headers, params: { scope_key: "company:#{company.id}", history_page: 1 }
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{foreign.id}/relationship/configuration", headers: headers, params: { history_page: 1 }
    expect(response).to have_http_status(:forbidden)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    get url, headers: headers, params: { history_page: 1 }
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('history')
  end

  it 'rejects malformed pages, bounds sizes and preserves exact version filters when paging' do
    history
    get url, headers: headers, params: { history_page: ['1'] }
    expect(response).to have_http_status(:unprocessable_entity)
    get url, headers: headers, params: { history_per_page: 'bad' }
    expect(response).to have_http_status(:unprocessable_entity)
    get url, headers: headers, params: { history_page: 1, history_per_page: 500, source_version: 1 }
    expect(response.parsed_body.fetch('history_meta')).to eq('page' => 1, 'per_page' => 50, 'total' => 1)
    expect(response.parsed_body.fetch('history').pluck('version')).to eq([1])
  end

  it 'returns a genuine empty unsaved configuration history without creating records or audit' do
    before = [JrcRelationship::Configuration.count, JrcRelationship::ConfigurationVersion.count, JrcCrm::AuditEvent.count]
    get url, headers: headers, params: { history_page: 1, history_per_page: 25 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('history')).to eq([])
    expect(response.parsed_body.fetch('history_meta')).to eq('page' => 1, 'per_page' => 25, 'total' => 0)
    expect([JrcRelationship::Configuration.count, JrcRelationship::ConfigurationVersion.count, JrcCrm::AuditEvent.count]).to eq(before)
  end
end
