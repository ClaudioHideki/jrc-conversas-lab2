require 'rails_helper'

RSpec.describe 'Call Center native routing write authority', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, name: 'SYNTHETIC routing', code: 'ROUTE', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, name: 'SYNTHETIC routing', code: 'ROUTE') }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/routing_rules" }
  let(:attributes) do
    { routing_rule: { version: 1, rule_key: 'synthetic-route', kind: 'ddd', source_value: '11', target_unit_id: unit.id,
                      target_queue_id: queue.id, priority: 1, state: 'draft' } }
  end
  let(:rows) { JrcContactCenter::RoutingRule.where(account: account) }

  before { account.enable_features!('jrc_contact_center') }

  it 'preserves native authorized draft creation and editing without claiming publication' do
    post endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:created)
    record = rows.sole
    expect(record).to have_attributes(state: 'draft', created_by_account_user_id: member.id, source_value: '11')
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token,
                                      params: { routing_rule: { source_value: '21', priority: 2 } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload).to have_attributes(state: 'draft', source_value: '21', priority: 2)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'keeps provider publication unavailable even with explicitly granted publish authority' do
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account,
                                permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_publish])
    member.update!(custom_role: role)
    post endpoint, headers: actor.create_new_auth_token,
                   params: { routing_rule: attributes.fetch(:routing_rule).merge(state: 'published') }, as: :json
    expect(response).to have_http_status(:not_implemented)
    expect(response.parsed_body.fetch('error')).to eq('provider_capability_unavailable')
    expect(rows).to be_empty
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'does not mutate an existing published historical version' do
    data = attributes.fetch(:routing_rule).merge(state: 'published', account: account, created_by_account_user: member)
    record = JrcContactCenter::RoutingRule.create!(data)
    before = record.attributes.deep_dup
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token,
                                      params: { routing_rule: { source_value: '21', state: 'draft' } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('published_rule_immutable')
    expect(record.reload.attributes).to eq(before)
  end

  it 'preserves a legacy queue-only destination and advanced conditions/window during a common-field edit' do
    original = attributes.fetch(:routing_rule).merge(target_unit_id: nil, account: account, created_by_account_user: member,
                                                     starts_at: 1.hour.ago, ends_at: 1.hour.from_now,
                                                     conditions: { 'legacy' => 'SYNTHETIC preserved condition' })
    record = JrcContactCenter::RoutingRule.create!(original)
    before = record.reload.attributes.slice('target_unit_id', 'target_queue_id', 'conditions', 'starts_at', 'ends_at')
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token,
                                      params: { routing_rule: { source_value: '21' },
                                                expected_revision: JrcContactCenter::ConfigurationRevision.token(record) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload.source_value).to eq('21')
    expect(record.attributes.slice(*before.keys)).to eq(before)
  end

  it 'does not accept caller supplied identity as permission to use another account target' do
    remote = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: remote, name: 'SYNTHETIC foreign', code: 'OTHER', kind: 'sac')
    input = attributes.fetch(:routing_rule).merge(target_unit_id: foreign_unit.id, account_id: remote.id, created_by_account_user_id: member.id)
    post endpoint, headers: actor.create_new_auth_token, params: { routing_rule: input }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(rows).to be_empty
    expect(JrcContactCenter::RoutingRule.where(account: remote)).to be_empty
  end

  it 'returns a canonical revision and rejects stale edits without changing the draft' do
    post endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    record = rows.sole
    get "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    revision = response.parsed_body.fetch('item').fetch('revision')
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token,
                                      params: { routing_rule: { priority: 2 }, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:ok)
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token,
                                      params: { routing_rule: { priority: 3 }, expected_revision: revision }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(record.reload.priority).to eq(2)
  end

  it 'denies routing reads and writes across a current native business-unit boundary' do
    company = account.master_companies.create!(name: 'SYNTHETIC routing boundary', relationship_type: 'internal')
    alpha = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'A', name: 'SYNTHETIC routing A')
    beta = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'B', name: 'SYNTHETIC routing B')
    unit.update!(settings: { issuer_company_id: company.id, business_unit_id: alpha.id })
    other = JrcContactCenter::Unit.create!(account: account, code: 'B', name: 'SYNTHETIC outside routing', kind: 'sac',
                                           settings: { issuer_company_id: company.id, business_unit_id: beta.id })
    record = JrcContactCenter::RoutingRule.create!(account: account, created_by_account_user: member, target_unit: other,
                                                   version: 1, rule_key: 'synthetic-outside', kind: 'ddd', priority: 1, state: 'draft')
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: alpha, active: true, structure_managed: true)
    get "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token, params: { routing_rule: { priority: 2 } }, as: :json
    expect(response).to have_http_status(:not_found)
    post endpoint, headers: actor.create_new_auth_token,
                   params: { routing_rule: attributes.fetch(:routing_rule).merge(target_unit_id: other.id, target_queue_id: nil) }, as: :json
    expect(response).to have_http_status(:not_found)
    get endpoint, headers: actor.create_new_auth_token, params: { page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(record.reload.priority).to eq(1)
  end

  it 'requires explicit corporate coverage before creating a draft in a configured structure' do
    company = account.master_companies.create!(name: 'SYNTHETIC no implicit coverage', relationship_type: 'internal')
    business = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'A', name: 'SYNTHETIC coverage')
    unit.update!(settings: { issuer_company_id: company.id, business_unit_id: business.id })
    post endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:not_found)
    expect(rows).to be_empty
  end

  [nil, false, ''].each do |invalid|
    it "rejects a supplied invalid routing revision #{invalid.inspect} without changing data" do
      post endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
      record = rows.sole
      patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token,
                                        params: { routing_rule: { priority: 2 }, expected_revision: invalid }, as: :json
      expect(response).to have_http_status(:precondition_required)
      expect(record.reload.priority).to eq(1)
    end
  end

  it 'uses native bounded pagination and exact authorized filtering without leaking a foreign rule' do
    22.times do |number|
      key = "synthetic-#{number.to_s.rjust(3, '0')}"
      data = attributes.fetch(:routing_rule).merge(rule_key: key, account: account, created_by_account_user: member)
      JrcContactCenter::RoutingRule.create!(data)
    end
    foreign = create(:account)
    person = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign, name: 'SYNTHETIC foreign list', code: 'FOREIGN', kind: 'sac')
    JrcContactCenter::RoutingRule.create!(account: foreign, created_by_account_user: foreign.account_users.find_by!(user: person),
                                          target_unit: foreign_unit, version: 1, rule_key: 'synthetic-foreign', kind: 'ddd',
                                          source_value: '11', priority: 1, state: 'draft')
    get endpoint, headers: actor.create_new_auth_token, params: { page: 2, per_page: 10, state: 'draft', kind: 'ddd' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').length).to eq(10)
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'pages' => 3, 'total' => 22)
    get endpoint, headers: actor.create_new_auth_token, params: { page: 1, per_page: 10, q: 'synthetic-021' }
    expect(response.parsed_body.fetch('items').map { |row| row.fetch('rule_key') }).to eq(['synthetic-021'])
    get endpoint, headers: actor.create_new_auth_token, params: { page: 3, per_page: 10, q: '' }
    expect(response.parsed_body.fetch('items').length).to eq(2)
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(22)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'appends native scoped before/after audits without exposing opaque legacy conditions' do
    account.enable_features!('audit_logs', 'custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
    member.update!(custom_role: role)
    data = attributes.fetch(:routing_rule).merge(conditions: { 'authorization' => 'SYNTHETIC_PRIVATE_ROUTE_CONDITION' })
    post endpoint, headers: actor.create_new_auth_token, params: { routing_rule: data }, as: :json
    expect(response).to have_http_status(:created)
    record = rows.sole
    patch "#{endpoint}/#{record.id}", headers: actor.create_new_auth_token, params: { routing_rule: { source_value: '21' } }, as: :json
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits",
        headers: actor.create_new_auth_token, params: { resource_type: 'routing_rule', resource_id: record.id, history: true }
    expect(response).to have_http_status(:ok)
    history = response.parsed_body.fetch('items')
    expect(history.length).to eq(2)
    expect(history.first).to include('resource_type' => 'routing_rule', 'before' => hash_including('source_value' => '11'),
                                     'after' => hash_including('source_value' => '21'))
    expect(history.last.fetch('omitted_fields')).to include('conditions')
    expect(response.body).not_to include('SYNTHETIC_PRIVATE_ROUTE_CONDITION', 'authorization')
    expect(history.first.dig('scopes', 'after')).to include('unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s)
  end

  it 'applies current and historical unit coverage to routing audit history and forced detail URLs' do
    account.enable_features!('audit_logs', 'custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
    member.update!(custom_role: role)
    company = account.master_companies.create!(name: 'SYNTHETIC routing audit issuer', relationship_type: 'internal')
    alpha = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'ALPHA', name: 'SYNTHETIC routing A')
    beta = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'BETA', name: 'SYNTHETIC routing B')
    unit.update!(settings: { issuer_company_id: company.id, business_unit_id: alpha.id })
    other_unit = JrcContactCenter::Unit.create!(account: account, name: beta.name, code: 'BETA', kind: 'sac',
                                                settings: { issuer_company_id: company.id, business_unit_id: beta.id })
    coverage = JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'GROUP', active: true, structure_managed: true)
    post endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:created)
    allowed_record = rows.sole
    second = attributes.fetch(:routing_rule).merge(rule_key: 'synthetic-beta', target_unit_id: other_unit.id, target_queue_id: nil)
    post endpoint, headers: actor.create_new_auth_token, params: { routing_rule: second }, as: :json
    expect(response).to have_http_status(:created)
    denied_record = rows.find_by!(rule_key: 'synthetic-beta')
    audit = Audited.audit_class.find_by!(associated: account, auditable_type: 'JrcContactCenter::RoutingRule', auditable_id: denied_record.id)
    coverage.update!(scope: 'BUSINESS_UNIT', company: company, business_unit: alpha)
    url = "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits"
    get url, headers: actor.create_new_auth_token, params: { resource_type: 'routing_rule', resource_id: allowed_record.id, history: true }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').length).to eq(1)
    get url, headers: actor.create_new_auth_token, params: { resource_type: 'routing_rule', resource_id: denied_record.id, history: true }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get "#{url}/#{audit.id}", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
