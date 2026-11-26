require 'rails_helper'

# Prepared native read-only API cases. Direct synthetic receipt creation in
# pagination cases is not evidence of a worker effect or operational activation.
RSpec.describe 'Current native multi-destination ending history', type: :request do
  self.use_transactional_tests = false
  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'
  include_context 'JRC Service Desk domain'

  let(:operator) { attempt_operator }
  let(:customer) { account.master_companies.create!(name: 'SYNTHETIC history customer') }
  let(:contact) { create(:contact, account: account, company_id: customer.id, name: 'SYNTHETIC private history requester') }
  let(:sd_account) { account }
  let(:sd_user) { operator.user }
  let(:sd_account_user) { operator }
  let(:sd_contact) { contact }
  let(:typed_mode) { 'automatic' }
  let(:crm_history_action) { { 'kind' => 'crm', 'parameters' => {} } }
  let(:typed_version) { publish_typed_schema_definition('actions' => history_actions) }
  let(:typed_origin) { completed_history_origin }
  let(:history_headers) { operator.user.create_new_auth_token }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Exclusive committed typed history database required' unless owned && !ApplicationRecord.connection.transaction_open?

    job = JrcContactCenter::EndingDestinationJob
    previous = job._test_adapter
    job.enable_test_adapter(ActiveJob::QueueAdapters::TestAdapter.new)
    example.run
  ensure
    job&.enable_test_adapter(previous)
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    operator.update!(crm_enabled: true)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_unit.id.to_s))
  end

  def history_actions
    project = JrcContactCenter::EndingActions::Catalogue.new(account: account).call.fetch('entries')
                                                        .find { |row| row.fetch('code') == 'SYNTHETIC_ORIGIN_RULE' }.fetch('actions').first
    [project, crm_history_action,
     { 'kind' => 'service_desk', 'parameters' => {
       'unit_id' => sd_unit.id.to_s, 'service_id' => nil,
       'attributes' => { 'title' => 'SYNTHETIC private history ticket', 'description' => 'SYNTHETIC history ticket details',
                         'status_id' => sd_status.id.to_s, 'priority_id' => sd_priority.id.to_s }
     } }]
  end

  def completed_history_origin
    call = new_origin_source_call
    call.update!(contact_id: contact.id, company_id: customer.id)
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    row = JrcContactCenter::Qualification.find_by!(account: account, account_user: operator, call_session: call)
    JrcContactCenter::QualificationManager.new(account: account, member: operator).complete!(
      row, { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' }
    )
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: row.id)
  end

  def history_attempt(kind = 'project_task', retry_of: nil)
    attributes = { account: account, origin: typed_origin, readiness: typed_readiness,
                   rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: kind, request_key: SecureRandom.uuid }
    if retry_of
      attributes[:retry_of] = retry_of
      attributes[:retry_requested_by_account_user_id] = operator.id
    end
    JrcContactCenter::EndingDestinationAttempt.create!(**attributes).reload
  end

  def execute_history_attempt(row)
    JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: account, attempt_id: row.id).call
  end

  def request_typed_history(query = {}, headers: history_headers, account_id: account.id)
    get "/api/v1/accounts/#{account_id}/jrc_contact_center/qualifications/#{typed_origin.source_qualification_id}/ending_attempts",
        headers: headers, params: { history_contract: 2 }.merge(query)
  end

  def history_native_counts
    [JrcProjects::Task.where(account: account).count, account.jrc_crm_leads.count,
     JrcServiceDesk::Ticket.where(account: account).count, JrcContactCenter::EndingDestinationExecution.where(account: account).count]
  end

  it 'returns an authorized empty typed page without any business effect or fabricated success' do
    request_typed_history
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.parsed_body).to include('contract_version' => 2, 'items' => [], 'qualification_id' => typed_origin.source_qualification_id.to_s)
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 0, 'pages' => 0)
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'keeps contract 1 as the unchanged default instead of leaking typed rows into legacy clients' do
    history_attempt
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{typed_origin.source_qualification_id}/ending_attempts",
        headers: history_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('contract_version' => 1, 'items' => [])
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'returns independent pending identities for three destinations without executing them on read or refresh' do
    rows = %w[project_task crm service_desk].map { |kind| history_attempt(kind) }
    2.times { request_typed_history }
    expect(response).to have_http_status(:ok)
    items = response.parsed_body.fetch('items')
    expect(items.map { |row| row.fetch('id') }).to match_array(rows.map { |row| "typed:#{row.id}" })
    expect(items).to all(include('ledger' => 'typed', 'outcome' => 'pending', 'target' => nil, 'can_reprocess_pending' => false))
    expect(response.body).not_to include(
      'integrity_sha256', 'private_definition', contact.name, contact.email.to_s.presence || 'SYNTHETIC_PRIVATE_EMAIL'
    )
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'exposes only the currently visible native Project reference after a real successful execution' do
    row = history_attempt
    execute_history_attempt(row)
    request_typed_history
    expect(response).to have_http_status(:ok)
    task = JrcProjects::Task.where(account: account).sole
    expect(response.parsed_body.fetch('items').sole).to include(
      'id' => "typed:#{row.id}", 'operation' => 'create_task', 'outcome' => 'succeeded',
      'target' => { 'kind' => 'project_task', 'id' => task.id.to_s, 'project_id' => task.project_id.to_s }
    )
    expect(response.body).not_to include(task.title)
    expect(history_native_counts).to eq([1, 0, 0, 1])
  end

  it 'retains the successful Project fact while immediately withholding a private reference after membership withdrawal' do
    execute_history_attempt(history_attempt)
    project = JrcProjects::Project.where(account: account).sole
    project.update!(visibility: 'private')
    project.project_members.where(account: account, user_id: operator.user_id).sole.destroy!
    request_typed_history
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => 'succeeded', 'result_code' => 'completed', 'target' => nil)
    expect(response.body).not_to include(project.name)
    expect(history_native_counts).to eq([1, 0, 0, 1])
  end

  it 'returns a native CRM Lead reference without serializing its identity or company details' do
    execute_history_attempt(history_attempt('crm'))
    request_typed_history
    expect(response).to have_http_status(:ok)
    lead = account.jrc_crm_leads.sole
    expect(response.parsed_body.fetch('items').sole.fetch('target')).to eq('kind' => 'crm_lead', 'id' => lead.id.to_s)
    expect(response.body).not_to include(lead.name, customer.name, contact.name)
    expect(history_native_counts).to eq([0, 1, 0, 1])
  end

  it 'hides the CRM reference after current native module permission is revoked without changing its historical success' do
    execute_history_attempt(history_attempt('crm'))
    account.enable_features!('custom_roles')
    permissions = %w[jrc_contact_center_view jrc_contact_center_operate]
    operator.update!(custom_role: create(:custom_role, account: account, permissions: permissions))
    request_typed_history
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => 'succeeded', 'target' => nil)
    expect(history_native_counts).to eq([0, 1, 0, 1])
  end

  it 'returns a native Service Desk ticket reference with native scope and show authorization' do
    execute_history_attempt(history_attempt('service_desk'))
    request_typed_history
    expect(response).to have_http_status(:ok)
    ticket = JrcServiceDesk::Ticket.where(account: account).sole
    expect(response.parsed_body.fetch('items').sole.fetch('target')).to eq('kind' => 'service_desk_ticket', 'id' => ticket.id.to_s)
    expect(response.body).not_to include(ticket.title, ticket.description, customer.name)
    expect(history_native_counts).to eq([0, 0, 1, 1])
  end

  it 'keeps a Service Desk success while hiding its target when the native module is disabled after execution' do
    execute_history_attempt(history_attempt('service_desk'))
    account.disable_features!('jrc_service_desk')
    request_typed_history
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => 'succeeded', 'target' => nil)
    expect(history_native_counts).to eq([0, 0, 1, 1])
  end

  it 'paginates a native unsuccessful retry chain in fixed pages without replaying any destination' do
    previous = nil
    22.times do
      previous = history_attempt(retry_of: previous)
      JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: previous, outcome: 'failed', result_code: 'destination_failure')
    end
    request_typed_history({ per_page: 100_000 })
    first = response.parsed_body
    request_typed_history({ page: 2, per_page: 100_000 })
    second = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect([first.fetch('items').length, second.fetch('items').length]).to eq([20, 2])
    expect(first.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 22, 'pages' => 2)
    expect(first.fetch('items').map { |row| row['id'] } & second.fetch('items').map { |row| row['id'] }).to eq([])
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'rejects an unknown or array contract selector without returning private history' do
    history_attempt
    request_typed_history({ history_contract: ['2'] })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_ending_history_request')
    request_typed_history({ history_contract: 'unreviewed' })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'does not let another agent borrow the original agent by supplying account_user or unit parameters' do
    row = history_attempt
    request_typed_history({ account_user_id: operator.id, unit_id: unit.id }, headers: headers_for_unrelated_agent)
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(row.request_key)
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'does not expose a known attendance through a different account identifier' do
    row = history_attempt
    request_typed_history(account_id: create(:account).id)
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(row.request_key)
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'clears access after current source corporate coverage is withdrawn' do
    row = history_attempt
    JrcCrm::UserBusinessUnit.where(account: account, user: operator.user).find_each { |entry| entry.update!(active: false) }
    request_typed_history
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(row.request_key)
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  it 'does not treat a read of a terminal failure as an explicit retry consent' do
    row = history_attempt
    JrcContactCenter::EndingDestinationOutcome.create!(account: account, attempt: row, outcome: 'failed', result_code: 'destination_failure')
    2.times { request_typed_history }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => 'failed', 'result_code' => 'destination_failure')
    expect(JrcContactCenter::EndingDestinationAttempt.where(account: account).count).to eq(1)
    expect(history_native_counts).to eq([0, 0, 0, 0])
  end

  def headers_for_unrelated_agent
    user = create(:user, :contact_center_eligible, account: account, role: :agent)
    user.create_new_auth_token
  end
end
