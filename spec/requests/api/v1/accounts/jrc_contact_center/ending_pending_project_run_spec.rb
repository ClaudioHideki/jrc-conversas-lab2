require 'rails_helper'

RSpec.describe 'Explicit selected pending Project automation', type: :request do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:operator) { attempt_operator }
  let(:source_origin) { completed_attempt_source(operator) }
  let(:operator_headers) { operator.user.create_new_auth_token }
  let(:pending_attempt) do
    JrcContactCenter::EndingActions::QueueProjectAttempt.new(
      account: account, origin_id: source_origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid
    ).call
  end

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable selected pending execution required' unless owned
    raise 'Independent native pending execution required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    JrcContactCenter::EndingActions::ActivateRule.new(
      account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid,
      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
    ).call
  end

  def review_document(row = pending_attempt)
    { 'confirmed' => true, 'expected_request_key' => row.request_key, 'expected_version_id' => row.version_id.to_s }
  end

  def request_run(document = review_document, headers: operator_headers, qualification_id: source_origin.source_qualification_id,
                  attempt_id: pending_attempt.id, account_id: account.id)
    post(
      "/api/v1/accounts/#{account_id}/jrc_contact_center/qualifications/#{qualification_id}/ending_attempts/#{attempt_id}/reprocess",
      params: document.to_json, headers: headers.merge('CONTENT_TYPE' => 'application/json')
    )
  end

  def effect_counts
    [JrcProjects::Task.where(account: account).count,
     JrcContactCenter::EndingActionExecution.where(account: account).count,
     JrcContactCenter::EndingActionAttemptOutcome.where(account: account).count]
  end

  it 'creates one native Task as the original nonadministrator without changing qualification or ACW data' do
    row = pending_attempt
    qualification = JrcContactCenter::Qualification.find(source_origin.source_qualification_id)
    previous = qualification.attributes
    request_run
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('attempt_id' => row.id.to_s, 'outcome' => 'succeeded', 'result_code' => 'completed')
    expect(effect_counts).to eq([1, 1, 1])
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(operator.user_id)
    expect(JrcContactCenter::EndingActionExecution.where(account: account).sole.actor_account_user_id).to eq(operator.id)
    expect(qualification.reload.attributes).to eq(previous)
    expect(operator.reload.role).to eq('agent')
  end

  it 'does not invoke the qualification-wide dispatcher or complete another eligible pending rule' do
    project = JrcProjects::Project.where(account: account).sole
    second_input = origin_rule_document(project).merge('code' => 'SYNTHETIC_SECOND_PENDING', 'name' => 'SYNTHETIC second pending')
    JrcContactCenter::EndingActions::ConfigureRule.new(
      account: account, member: member, input: second_input, expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
    ).call
    JrcContactCenter::EndingActions::ActivateRule.new(
      account: account, member: member, rule_code: second_input.fetch('code'), request_key: SecureRandom.uuid,
      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
    ).call
    first = pending_attempt
    second = JrcContactCenter::EndingActions::QueueProjectAttempt.new(
      account: account, origin_id: source_origin.id, rule_code: second_input.fetch('code'), request_key: SecureRandom.uuid
    ).call
    request_run
    expect(response).to have_http_status(:ok)
    expect(first.reload.outcome.outcome).to eq('succeeded')
    expect(second.reload.outcome).to be_nil
    expect(effect_counts).to eq([1, 1, 1])
    expect(JrcContactCenter::EndingActionAttempt.where(account: account).count).to eq(2)
  end

  it 'rejects reprocessing a completed result rather than creating a second effect or attempt' do
    request_run
    first = response.parsed_body
    request_run
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('ending_attempt_no_longer_pending')
    expect(pending_attempt.reload.outcome.outcome).to eq(first.fetch('outcome'))
    expect(effect_counts).to eq([1, 1, 1])
    expect(JrcContactCenter::EndingActionAttempt.where(account: account).count).to eq(1)
  end

  it 'requires literal explicit confirmation and rejects caller-supplied actor or destination fields' do
    [false, nil, 'true'].each do |value|
      request_run(review_document.merge('confirmed' => value))
      expect(response).to have_http_status(:unprocessable_entity)
    end
    request_run(review_document.merge('user_id' => actor.id, 'unit_id' => unit.id, 'parameters' => {}))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(effect_counts).to eq([0, 0, 0])
    expect(pending_attempt.reload.outcome).to be_nil
  end

  it 'rejects a changed immutable version or request identity without silently selecting a newer rule' do
    request_run(review_document.merge('expected_version_id' => (pending_attempt.version_id + 1).to_s))
    expect(response).to have_http_status(:conflict)
    request_run(review_document.merge('expected_request_key' => SecureRandom.uuid))
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('ending_pending_review_changed')
    expect(effect_counts).to eq([0, 0, 0])
    expect(pending_attempt.reload.outcome).to be_nil
  end

  it 'keeps another agent read-only even for an explicit auditor with native Project creation authority' do
    pending_attempt
    account.enable_features!('custom_roles')
    permissions = %w[jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_supervise jrc_contact_center_audit
                     jrc_projects_project_view jrc_projects_task_create]
    role = create(:custom_role, account: account, permissions: permissions)
    member.update!(custom_role: role, jrc_projects_permissions: member.jrc_projects_permissions.merge('projects.task.create' => true))
    project = JrcProjects::Project.where(account: account).sole
    expect(JrcProjects::Authorization).to be_allowed(account_user: member, capability: 'projects.task.create', project: project)
    request_run(review_document, headers: actor.create_new_auth_token)
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(pending_attempt.request_key)
    expect(effect_counts).to eq([0, 0, 0])
    expect(pending_attempt.reload.outcome).to be_nil
  end

  it 'binds the selected attempt to the authorized qualification rather than accepting a known foreign id' do
    pending_attempt
    other_origin = completed_attempt_source(operator)
    request_run(qualification_id: other_origin.source_qualification_id)
    expect(response).to have_http_status(:not_found)
    expect(effect_counts).to eq([0, 0, 0])
    expect(pending_attempt.reload.outcome).to be_nil
  end

  it 'does not revive a formerly pending action after disabling and reactivating its rule' do
    row = pending_attempt
    previous = row.attributes
    project = JrcProjects::Project.where(account: account).sole
    [false, true].each do |active|
      JrcContactCenter::EndingActions::ConfigureRule.new(
        account: account, member: member, input: origin_rule_document(project).merge('active' => active),
        expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
      ).call
    end
    # Admission refuses before the worker; it must not fabricate a terminal
    # receipt. The immutable intervening rule version is the permanent barrier.
    2.times do
      request_run
      expect([response.status, response.parsed_body.fetch('error')]).to eq([422, 'ending_action_pending_permanently_blocked'])
    end
    expect(row.reload.attributes).to eq(previous)
    expect(row.outcome).to be_nil
    expect(effect_counts).to eq([0, 0, 0])
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created')).to be_empty
  end

  it 'revalidates current native Project permission without changing an unauthorized pending operation' do
    pending_attempt
    JrcProjects::ProjectMember.where(account: account, user_id: operator.user_id).sole.update!(role: 'viewer')
    request_run
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(pending_attempt.request_key)
    expect(effect_counts).to eq([0, 0, 0])
    expect(pending_attempt.reload.outcome).to be_nil
  end

  it 'denies a foreign-account qualification even for an independently authenticated eligible operator there' do
    pending_attempt
    other = create(:account)
    other.enable_features!('jrc_contact_center')
    person = create(:user, :contact_center_eligible, account: other, role: :agent)
    membership = other.account_users.find_by!(user: person)
    context = { account: other, account_user: membership, user: person }
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center)).to be_operate
    request_run(review_document, headers: person.create_new_auth_token, account_id: other.id)
    expect(response).to have_http_status(:not_found)
    expect(effect_counts).to eq([0, 0, 0])
    expect(pending_attempt.reload.outcome).to be_nil
  end

  it 'rolls back native Task and success on a real outcome write failure and never retries that terminal failure' do
    row = pending_attempt
    connection = ApplicationRecord.connection
    previous_timeout = connection.select_value('SHOW lock_timeout')
    constraint = "cc_pending_run_#{SecureRandom.hex(6)}"
    installed = false
    begin
      connection.execute("SET lock_timeout = '5s'")
      statement = "ALTER TABLE jrc_contact_center_ending_action_attempt_outcomes ADD CONSTRAINT #{constraint}"
      connection.execute("#{statement} CHECK (attempt_id <> #{row.id} OR outcome <> 'succeeded')")
      installed = true
      request_run
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('outcome' => 'failed', 'result_code' => 'destination_failure')
      expect(effect_counts).to eq([0, 0, 1])
    ensure
      connection.execute("ALTER TABLE jrc_contact_center_ending_action_attempt_outcomes DROP CONSTRAINT #{constraint}") if installed
      connection.execute("SET lock_timeout = #{connection.quote(previous_timeout)}")
    end
    request_run
    expect(response).to have_http_status(:conflict)
    expect(row.reload.outcome.outcome).to eq('failed')
    expect(effect_counts).to eq([0, 0, 1])
  end

  it 'does not carry the read transaction into the independent native effect boundary' do
    row = pending_attempt
    command = JrcContactCenter::EndingActions::RunPendingProjectAttempt.new(
      account: account, member: operator, qualification_id: source_origin.source_qualification_id,
      attempt_id: row.id, review: review_document(row)
    )
    expect { Account.transaction { command.call } }.to raise_error do |error|
      expect(error.class.name).to eq('JrcContactCenter::OperationError')
      expect(error.code).to eq('ending_execution_requires_independent_transaction')
    end
    expect(effect_counts).to eq([0, 0, 0])
    expect(row.reload.outcome).to be_nil
  end
end
