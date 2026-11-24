require 'rails_helper'

RSpec.describe 'Authorized native ending attempt history', type: :request do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable ending history database required' unless owned
    raise 'Committed ending history fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:headers) { actor.create_new_auth_token }
  let(:attempt) do
    complete_origin_qualification
    JrcContactCenter::EndingActions::QueueProjectAttempt.new(account: account, origin_id: origin.id,
                                                             rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid).call
  end

  before do
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: SecureRandom.uuid,
                                                      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def request_history(id = qualification.id, request_headers = headers, params = {})
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{id}/ending_attempts", headers: request_headers, params: params
  end

  def history_effects
    [JrcProjects::Task.where(account: account).count,
     JrcContactCenter::EndingActionExecution.where(account: account).count,
     JrcContactCenter::EndingActionAttempt.where(account: account).count,
     JrcContactCenter::EndingActionAttemptOutcome.where(account: account).count]
  end

  it 'returns an empty authorized list without fabricating success or starting ACW' do
    original = qualification.attributes
    request_history
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([])
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 0, 'pages' => 0)
    expect(qualification.reload.attributes).to eq(original)
    expect(history_effects).to eq([0, 0, 0, 0])
  end

  it 'returns durable pending work with a bounded allowlist and no private configuration' do
    row = attempt
    request_history
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to eq('no-store')
    item = response.parsed_body.fetch('items').sole
    expect(item).to include('id' => row.id.to_s, 'outcome' => 'pending', 'target' => nil, 'result_code' => nil)
    expect(item.keys).to match_array(%w[id origin_id rule_code version_id destination_kind request_id queued_at
                                        outcome result_code finished_at execution_id target])
    expect(response.body).not_to include('private_definition', 'SYNTHETIC unarmed original evidence', 'integrity_sha256', 'notes')
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'returns a current native target reference only after an actual successful execution' do
    result = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: attempt.id).call
    request_history
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('items').sole
    task = JrcProjects::Task.where(account: account).sole
    expect(item).to include('outcome' => 'succeeded', 'result_code' => 'completed', 'execution_id' => result.execution_id.to_s)
    expect(item.fetch('target')).to eq('kind' => 'project_task', 'id' => task.id.to_s, 'project_id' => task.project_id.to_s)
    expect(response.body).not_to include(task.title)
    expect(history_effects).to eq([1, 1, 1, 1])
  end

  it 'retains the success fact while hiding a destination disabled after execution' do
    JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: attempt.id).call
    account.disable_features!('jrc_projects')
    request_history
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => 'succeeded', 'target' => nil)
    expect(history_effects).to eq([1, 1, 1, 1])
  end

  it 'shows a bounded refusal without retrying after the destination becomes available again' do
    row = attempt
    account.disable_features!('jrc_projects')
    result = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: row.id).call
    account.enable_features!('jrc_projects')
    2.times { request_history }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => result.outcome, 'result_code' => 'reference_unavailable')
    expect(history_effects).to eq([0, 0, 1, 1])
  end

  it 'revalidates own current operate permission without borrowing administrator defaults' do
    attempt
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view]))
    request_history
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_ORIGIN_RULE')
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'does not let an administrator inspect another original agent without explicit audit authority' do
    original = completed_attempt_source(attempt_operator)
    request_history(original.source_qualification_id)
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_ORIGIN_RULE')
    expect(history_effects).to eq([0, 0, 0, 0])
  end

  it 'allows an explicitly authorized auditor only within the current native call scope' do
    original = completed_attempt_source(attempt_operator)
    own_qualification = qualification
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account,
                                permissions: %w[jrc_contact_center_view jrc_contact_center_supervise jrc_contact_center_audit])
    member.update!(custom_role: role)
    request_history(original.source_qualification_id)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('qualification_id')).to eq(original.source_qualification_id.to_s)
    expect(response.parsed_body.fetch('items')).to eq([])
    request_history(own_qualification.id)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('qualification_id')).to eq(own_qualification.id.to_s)
    expect(history_effects).to eq([0, 0, 0, 0])
  end

  it 'keeps a successful own receipt but removes a private project link immediately after membership is revoked' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    row = JrcContactCenter::EndingActions::QueueProjectAttempt.new(account: account, origin_id: original.id,
                                                                   rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid).call
    JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: row.id).call
    project = JrcProjects::Project.where(account: account).sole
    project.update!(visibility: 'private')
    own_headers = operator.user.create_new_auth_token
    request_history(original.source_qualification_id, own_headers)
    expect(response.parsed_body.fetch('items').sole.fetch('target')).to be_present
    project.project_members.where(account: account, user_id: operator.user_id).sole.destroy!
    request_history(original.source_qualification_id, own_headers)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('outcome' => 'succeeded', 'target' => nil)
    expect(response.body).not_to include(project.name)
    expect(history_effects).to eq([1, 1, 1, 1])
  end

  it 'does not let an ordinary operator inspect another original agent by supplying identifiers' do
    attempt
    operator = attempt_operator
    request_history(qualification.id, operator.user.create_new_auth_token,
                    { user_id: member.user_id, account_user_id: member.id, unit_id: unit.id })
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(attempt.request_key)
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'does not leak another account qualification through a known numeric identifier' do
    attempt
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/jrc_contact_center/qualifications/#{qualification.id}/ending_attempts", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(attempt.request_key)
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'does not return technical history while the native Call Center feature is disabled' do
    attempt
    account.disable_features!('jrc_contact_center')
    request_history
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC_ORIGIN_RULE')
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'denies a known own attendance after corporate coverage moves to a different business unit' do
    attempt
    JrcCrm::UserBusinessUnit.where(account: account, user: actor).find_each { |row| row.update!(active: false) }
    other_company = JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC other issuer', relationship_type: 'internal', active: true)
    other_unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: other_company,
                                              name: 'SYNTHETIC other business', code: 'SYNTHETIC_OTHER', active: true)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: other_company,
                                     business_unit: other_unit, active: true, structure_managed: true)
    request_history
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(attempt.request_key)
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'bounds a page to twenty records even when the caller requests an unbounded result' do
    attempt
    21.times do
      JrcContactCenter::EndingActions::QueueProjectAttempt.new(account: account, origin_id: origin.id,
                                                               rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid).call
    end
    request_history(qualification.id, headers, { per_page: 100_000 })
    first = response.parsed_body
    request_history(qualification.id, headers, { page: 2, per_page: 100_000 })
    second = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(first.fetch('items').length).to eq(20)
    expect(second.fetch('items').length).to eq(2)
    expect(first.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 22, 'pages' => 2)
    expect(first.fetch('items').map { |row| row['id'] } & second.fetch('items').map { |row| row['id'] }).to eq([])
    expect(history_effects).to eq([0, 0, 22, 0])
  end

  it 'returns an empty later page without reusing stale records or executing pending work' do
    attempt
    request_history(qualification.id, headers, { page: 100 })
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([])
    expect(response.parsed_body.fetch('meta')).to include('page' => 100, 'total' => 1, 'pages' => 1)
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'rejects an array pagination parameter with a bounded error rather than a server failure' do
    attempt
    request_history(qualification.id, headers, { page: ['1'] })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_ending_history_page')
    expect(history_effects).to eq([0, 0, 1, 0])
  end

  it 'rejects a malformed qualification identifier without trying to infer another source' do
    attempt
    request_history('SYNTHETIC_INVALID')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_ending_history_request')
    expect(history_effects).to eq([0, 0, 1, 0])
  end
end
