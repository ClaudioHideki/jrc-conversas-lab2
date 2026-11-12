require 'rails_helper'

# Native PostgreSQL/HTTP acceptance. Prepared against existing fixture patterns;
# must run in the complete repository after the additive migration. Never run
# migrations or these synthetic writes in a customer/production database.
RSpec.describe 'Backoffice typed requirement catalog and captured plans', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contact: contact, owner: admin, requested_by: admin,
      title: 'Synthetic typed requirements', stage: 'documentation', metadata: { finance_required: false })
  end
  let(:catalog_url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requirement_rules" }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/requirements" }
  let(:definition) do
    { label: 'Synthetic signer information', kind: 'information', answer_type: 'text', stage: 'documentation', required: true, blocking: true }
  end
  let(:intent) { SecureRandom.uuid }
  before { account.enable_features!('jrc_crm') }

  def publish(definition:, **scope)
    post catalog_url, headers: headers, as: :json,
      params: { intent: intent, version: 0, reason: 'Synthetic reviewed configuration', rule: { definition: definition, state: 'active', **scope } }
    expect(response).to have_http_status(:created), response.body
    response.parsed_body
  end

  def answer(key:, value:, revision: 0)
    plan = JrcBackoffice::Requirements.current(operation)
    post "#{url}/answer", headers: headers, as: :json,
      params: { key: key, plan_revision: plan.version, response_revision: revision,
        answer: { value: value }, reason: 'Synthetic analyst confirmation' }
  end

  it 'publishes an immutable revision and captures it only in a new request' do
    published = publish(definition: definition)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('items').first).to include('key' => published['rule_key'], 'blocking' => true, 'status' => 'missing')
    expect(JrcBackoffice::Requirements.current(operation).entries.first['rule_version']).to eq(1)
  end

  it 'does not silently adopt new rules in an existing request' do
    operation
    publish(definition: definition)
    get url, headers: headers
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(JrcBackoffice::Requirements.current(operation).version).to eq(1)
    post "#{url}/adopt", headers: headers, as: :json, params: { revision: 1, reason: 'Reviewed new checklist' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('plan_revision')).to eq(2)
    expect(operation.requirement_plans.count).to eq(2)
  end

  it 'replays the same creation intent without adding another rule or audit event' do
    first = publish(definition: definition)
    baseline = account.jrc_crm_audit_events.count
    second = publish(definition: definition)
    expect(second).to eq(first)
    expect(JrcBackoffice::RequirementRule.where(account: account, rule_key: intent).count).to eq(1)
    expect(account.jrc_crm_audit_events.count).to eq(baseline)
  end

  it 'refuses a changed creation intent or stale edit without replacing the rule' do
    publish(definition: definition)
    post catalog_url, headers: headers, as: :json,
      params: { intent: intent, version: 0, reason: 'Changed payload', rule: { definition: definition.merge(label: 'Changed'), state: 'active' } }
    expect(response).to have_http_status(:conflict)
    expect(JrcBackoffice::RequirementRule.find_by!(account: account, rule_key: intent).definition['label']).to eq(definition[:label])
  end

  it 'archives by appending a revision and preserves the captured checklist' do
    rule = publish(definition: definition)
    operation
    patch "#{catalog_url}/#{rule['rule_key']}", headers: headers, as: :json,
      params: { version: 1, reason: 'Archive for future requests', rule: { definition: definition, state: 'archived' } }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['version']).to eq(2)
    get url, headers: headers
    expect(response.parsed_body.fetch('items').first['blocking']).to be(true)
  end

  it 'rejects arrays in scope identifiers instead of publishing an account-wide rule' do
    post catalog_url, headers: headers, as: :json,
      params: { intent: intent, version: 0, reason: 'Invalid synthetic scope', rule: { definition: definition, product_id: [1] } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcBackoffice::RequirementRule.where(account: account)).not_to exist
  end

  it 'does not let a foreign account identifier or unsupported field broaden publication' do
    post catalog_url, headers: headers, as: :json,
      params: { intent: intent, version: 0, reason: 'Forged account', rule: { definition: definition, account_id: create(:account).id } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcBackoffice::RequirementRule.where(account: account)).not_to exist
  end

  it 'denies catalog mutation to an agent without changing any roles' do
    agent = create(:user, account: account, role: :agent)
    before = account.account_users.find_by!(user: agent).attributes.deep_dup
    post catalog_url, headers: agent.create_new_auth_token, as: :json,
      params: { intent: intent, version: 0, reason: 'Unauthorized', rule: { definition: definition } }
    expect(response).to have_http_status(:unauthorized)
    expect(account.account_users.find_by!(user: agent).attributes).to eq(before)
    expect(JrcBackoffice::RequirementRule.where(account: account)).not_to exist
  end

  it 'requires full native coverage for account-wide configuration' do
    issuer = account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Synthetic unit', code: SecureRandom.hex(8), company_id: issuer.id)
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    get catalog_url, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'never exposes the request checklist to a foreign tenant or unassigned agent' do
    publish(definition: definition)
    foreign = create(:user, account: create(:account), role: :administrator)
    get url, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    agent = create(:user, account: account, role: :agent)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'persists an explicit false answer with its audit without rewriting the plan' do
    rule = publish(definition: definition.merge(answer_type: 'boolean'))
    plan = JrcBackoffice::Requirements.current(operation)
    before = plan.attributes.deep_dup
    answer(key: rule['rule_key'], value: false)
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('items').first['status']).to eq('satisfied')
    expect(plan.reload.attributes).to eq(before)
    expect(plan.responses.last.payload).to eq('value' => false)
    expect(account.jrc_crm_audit_events.where("metadata ->> 'action' = ?", 'requirement_answered')).to exist
  end

  it 'allows only the assigned analyst to answer and never grants configuration management' do
    rule = publish(definition: definition)
    agent = create(:user, account: account, role: :agent)
    operation.update!(owner: agent)
    post "#{url}/answer", headers: agent.create_new_auth_token, as: :json,
      params: { key: rule['rule_key'], plan_revision: 1, response_revision: 0, answer: { value: 'Synthetic response' }, reason: 'Reviewed' }
    expect(response).to have_http_status(:ok), response.body
    get catalog_url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'blocks advancing required information until it is actually supplied' do
    rule = publish(definition: definition)
    expect { operation.advance!(actor: admin) }.to raise_error(JrcBackoffice::Requirements::Blocked)
    expect(operation.reload.stage).to eq('documentation')
    answer(key: rule['rule_key'], value: 'Synthetic contact')
    expect(response).to have_http_status(:ok), response.body
    expect { operation.advance!(actor: admin) }.not_to raise_error
  end

  it 'keeps a rejected manual validation blocking until a new explicit decision' do
    rule = publish(definition: definition.except(:answer_type).merge(kind: 'validation', source: 'manual_review'))
    post "#{url}/answer", headers: headers, as: :json,
      params: { key: rule['rule_key'], plan_revision: 1, response_revision: 0, answer: { decision: 'rejected' }, reason: 'Divergence' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('items').first).to include('status' => 'rejected', 'blocking' => true)
  end

  it 'cannot satisfy a signature with a submitted boolean or manual decision' do
    rule = publish(definition: definition.except(:answer_type).merge(kind: 'signature', stage: 'contract'))
    plan = JrcBackoffice::Requirements.current(operation)
    post "#{url}/answer", headers: headers, as: :json,
      params: { key: rule['rule_key'], plan_revision: plan.version, response_revision: 0, answer: { decision: 'approved' }, reason: 'Not evidence' }
    expect(response).to have_http_status(:unprocessable_entity), response.body
    expect(plan.responses).not_to exist
  end

  it 'rejects stale response and plan versions without duplicate writes' do
    rule = publish(definition: definition)
    answer(key: rule['rule_key'], value: 'First')
    expect(response).to have_http_status(:ok)
    count = JrcBackoffice::Requirements.current(operation).responses.count
    answer(key: rule['rule_key'], value: 'Stale', revision: 0)
    expect(response).to have_http_status(:conflict)
    expect(JrcBackoffice::Requirements.current(operation).responses.count).to eq(count)
  end

  it 'denies direct UPDATE and DELETE of immutable answers at the database level' do
    rule = publish(definition: definition)
    answer(key: rule['rule_key'], value: 'Original')
    stored = JrcBackoffice::Requirements.current(operation).responses.last
    connection = ActiveRecord::Base.connection
    %W[UPDATE DELETE].each do |action|
      sql = action == 'UPDATE' ? "UPDATE #{stored.class.table_name} SET reason='changed' WHERE id=#{stored.id}" : "DELETE FROM #{stored.class.table_name} WHERE id=#{stored.id}"
      expect do
        ActiveRecord::Base.transaction(requires_new: true) { connection.execute(sql) }
      end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    end
    expect(stored.reload.payload).to eq('value' => 'Original')
  end

  it 'treats unknown customer type as unavailable rather than dispensing a required company document' do
    publish(definition: definition, customer_kind: 'company')
    get url, headers: headers
    expect(response.parsed_body.fetch('items').first).to include('status' => 'unavailable', 'blocking' => true)
  end

  it 'refuses an answer after the customer-kind evidence changes until explicit review' do
    rule = publish(definition: definition)
    operation
    company = account.master_companies.create!(name: 'Synthetic company', tax_id: '11222333000181')
    contact.update!(company_id: company.id)
    answer(key: rule['rule_key'], value: 'New source')
    expect(response).to have_http_status(:conflict)
    expect(JrcBackoffice::Requirements.current(operation).responses).not_to exist
  end

  it 'does not mutate a completed operation or auto activate its contract when answering' do
    rule = publish(definition: definition)
    operation.update!(status: 'completed', stage: 'completed', completed_at: Time.current)
    answer(key: rule['rule_key'], value: 'Not allowed')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(operation.reload.status).to eq('completed')
    expect(JrcBackoffice::Requirements.current(operation).responses).not_to exist
  end

  it 'filters the private dynamic answer from request logs' do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter('answer' => { 'value' => 'Private signer value' })
    expect(filtered).to eq('answer' => '[FILTERED]')
  end
  it 'shows exact immutable answer revisions through a scoped paginated read' do
    rule = publish(definition: definition)
    answer(key: rule['rule_key'], value: 'First historical answer')
    answer(key: rule['rule_key'], value: 'Second historical answer', revision: 1)
    count = JrcBackoffice::RequirementResponse.count
    get "#{url}/history", headers: headers, params: { key: rule['rule_key'], plan_revision: 1 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('data').map { |row| row.fetch('payload').fetch('value') }).to eq(['Second historical answer', 'First historical answer'])
    expect(JrcBackoffice::RequirementResponse.count).to eq(count)
  end

  it 'does not expose a previous customer answer after the request changes customer context' do
    rule = publish(definition: definition)
    answer(key: rule['rule_key'], value: 'PRIVATE CUSTOMER VALUE')
    operation.update!(contact: create(:contact, account: account))
    get "#{url}/history", headers: headers, params: { key: rule['rule_key'], plan_revision: 1 }
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('PRIVATE CUSTOMER VALUE')
    get url, headers: headers
    expect(response.parsed_body['stale']).to be(true)
    expect(response.body).not_to include('PRIVATE CUSTOMER VALUE')
  end

  it 'does not confuse the company post-signature gate with a pre-send approval' do
    predicate = JrcBackoffice::RequirementDefinition
    expect(predicate.post_signature?('kind' => 'approval', 'source' => 'contracts.company_signature')).to be(true)
    expect(predicate.post_signature?('kind' => 'approval', 'source' => 'backoffice.release')).to be(false)
  end

  it 'reports native configuration capability without exposing catalog records' do
    get "#{catalog_url}/capabilities", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('can_manage' => true)
    agent = create(:user, account: account, role: :agent)
    get "#{catalog_url}/capabilities", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('can_manage' => false)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

end
