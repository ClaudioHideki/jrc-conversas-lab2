require 'rails_helper'

RSpec.describe 'Native exact configuration history lookup', type: :request do
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

  it 'retrieves an exact stored version older than the recent fifty while preserving the current definition and history' do
    history
    before = [configuration.attributes, configuration.versions.count, JrcCrm::AuditEvent.count]
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('history').pluck('version')).to eq(76.downto(27).to_a)
    get url, headers: headers, params: { source_version: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.slice('scope_key', 'version')).to eq('scope_key' => 'account', 'version' => 76)
    expect(response.parsed_body.fetch('history').pluck('version')).to eq([1])
    expect([configuration.reload.attributes, configuration.versions.count, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'restores the older source through the native governed writer without changing its original versions' do
    stored = history.map(&:attributes)
    post "#{url}/restore", headers: headers, as: :json,
                           params: { scope_key: 'account', version: 76, source_version: 1, reason: 'Review an older stored definition' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('scope_key' => 'account', 'version' => 77, 'restored_from_version' => 1)
    expect(configuration.versions.where(version: 1..76).order(:version).map(&:attributes)).to eq(stored)
    expect(configuration.reload.version).to eq(77)
  end

  it 'rejects malformed explicit versions and returns no invented source for an absent version' do
    configuration
    %w[0 -1 1.5 invalid 2147483648].each do |value|
      get url, headers: headers, params: { source_version: value }
      expect(response).to have_http_status(:unprocessable_entity)
    end
    get url, headers: headers, params: { source_version: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('history')).to eq([])
  end

  it 'retains native account, company scope and configure access when selecting a source' do
    configuration
    foreign = create(:account)
    company = create(:company, account: foreign)
    get url, headers: headers, params: { scope_key: "company:#{company.id}", source_version: 1 }
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{foreign.id}/relationship/configuration", headers: headers, params: { source_version: 1 }
    expect(response).to have_http_status(:forbidden)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    get url, headers: headers, params: { source_version: 1 }
    expect(response).to have_http_status(:forbidden)
  end
end
