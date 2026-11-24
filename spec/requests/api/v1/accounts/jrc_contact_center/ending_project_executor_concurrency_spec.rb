require 'rails_helper'
require 'timeout'
require 'stringio'

# PRIVATE CANDIDATE: requires owned receipt installation and explicit CI admission.
RSpec.describe 'Native ending Projects destination effects and immutable receipts' do
  self.use_transactional_tests = false

  around do |example|
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable ending executor database required' unless owned
    raise 'Committed ending executor fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native ending execution original evidence'

  before do
    activate_execution_rule
  end

  def activate_execution_rule
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: SecureRandom.uuid,
                                                      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def revise_execution_rule(changes)
    project = JrcProjects::Project.where(account: account).sole
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member,
                                                       input: origin_rule_document(project).merge(changes),
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def execute_native_project(original_id = origin.id, target_account = account)
    JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: target_account, origin_id: original_id,
                                                            rule_code: 'SYNTHETIC_ORIGIN_RULE').call
  end

  def destination_effects
    [JrcProjects::Task.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
     JrcContactCenter::EndingActionExecution.where(account: account).count]
  end

  def waiting_executor(state)
    ids = [account.id, origin.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:result] << execute_native_project(ids.last, Account.find(ids.first))
      end
    rescue StandardError => e
      state[:result] << e
    end
  end

  def wait_for_executor_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
  end

  def join_executors(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Synthetic destination worker remained active' if worker.alive?
    end
  end

  def capture_execution_sql
    previous = ActiveRecord::Base.logger
    output = StringIO.new
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(output)
    yield
    output.string
  ensure
    ActiveRecord::Base.logger = previous
  end

  def second_original_operator
    person = create(:user, :contact_center_eligible, account: account, role: :agent)
    operator = account.account_users.find_by!(user: person)
    operator.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.task.create' => true })
    JrcCrm::UserBusinessUnit.create!(account: account, user: person, scope: 'GROUP', active: true, structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: operator, active: true, role: 'agent', priority: 1)
    project = JrcProjects::Project.where(account: account).sole
    JrcProjects::ProjectMember.create!(account: account, project: project, user: person, role: 'member')
    operator
  end

  def completed_origin_for(operator)
    call = new_origin_source_call
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    qualification = JrcContactCenter::Qualification.find_by!(account: account, account_user: operator, call_session: call)
    JrcContactCenter::QualificationManager.new(account: account, member: operator).complete!(
      qualification, { reason_code: 'SYNTHETIC_ORIGIN_REASON', outcome_code: 'completed' }
    )
    JrcContactCenter::EndingActionOrigin.find_by!(account: account, source_qualification_id: qualification.id)
  end

  it 'commits the actual native Task, its audit and one database-attested success together' do
    complete_origin_qualification
    receipt = execute_native_project
    expect(destination_effects).to eq([1, 1, 1])
    expect(receipt).to have_attributes(origin_id: origin.id, version_id: origin.version_id, actor_account_user_id: member.id,
                                       actor_user_id: actor.id, destination_kind: 'project_task', trigger_kind: 'ending_action_completion')
    task = JrcProjects::Task.where(account: account).sole
    expect(receipt.target_id).to eq(task.id)
    expect(task).to have_attributes(created_by_id: actor.id, title: 'SYNTHETIC unarmed original evidence')
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').sole.correlation_id).to eq(receipt.request_key)
  end

  it 'replays a committed success without creating another native Task, audit or receipt' do
    complete_origin_qualification
    first = execute_native_project.attributes
    expect(execute_native_project.attributes).to eq(first)
    expect(execute_native_project.attributes).to eq(first)
    expect(destination_effects).to eq([1, 1, 1])
  end

  it 'uses the original agent rather than the configuration manager for the task, audit and receipt' do
    operator = second_original_operator
    original = completed_origin_for(operator)
    context = { account: account, account_user: operator, user: operator.user }
    expect(JrcContactCenter::ModulePolicy.new(context, :contact_center).configure?).to be(false)
    receipt = JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      result = execute_native_project(original.id)
      expect(Current.account_user.id).to eq(member.id)
      expect(Current.user.id).to eq(actor.id)
      result
    end
    expect(receipt).to have_attributes(actor_account_user_id: operator.id, actor_user_id: operator.user_id)
    expect(receipt.readiness.actor_account_user_id).to eq(member.id)
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(operator.user_id)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').sole.actor_id).to eq(operator.user_id)
  end

  it 'does not borrow the configuration manager privilege after the original agent becomes a destination viewer' do
    operator = second_original_operator
    original = completed_origin_for(operator)
    JrcProjects::ProjectMember.where(account: account, user_id: operator.user_id).sole.update!(role: 'viewer')
    expect do
      JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
        execute_native_project(original.id)
      end
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'keeps the configured rule and native task content out of actual SQL logs and receipt inspection' do
    complete_origin_qualification
    receipt = nil
    log = capture_execution_sql { receipt = execute_native_project }
    expect(log).to include('jrc_contact_center_ending_action_executions', '[FILTERED]')
    expect(log).not_to include('SYNTHETIC_ORIGIN_RULE', 'SYNTHETIC unarmed original evidence')
    expect(receipt.inspect).to include('rule_code: [FILTERED]', 'request_key: [FILTERED]')
    expect(receipt.inspect).not_to include('SYNTHETIC_ORIGIN_RULE', receipt.request_key)
    expect(receipt.reload.rule_code).to eq('SYNTHETIC_ORIGIN_RULE')
    expect(JrcProjects::Task.where(account: account).sole.title).to eq('SYNTHETIC unarmed original evidence')
  end

  it 'does not treat a pending ACW or a draft result as a completed trigger' do
    original = origin
    expect { execute_native_project(original.id) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_trigger_pending')
    expect(qualification.reload.completed_at).to be_nil
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'leaves agent-confirmation rules without effects until their separate per-rule confirmation exists' do
    revise_execution_rule('execution_mode' => 'agent_confirmation')
    activate_execution_rule
    complete_origin_qualification
    expect { execute_native_project }.to raise_error(JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation')
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'rechecks destination access even when an earlier success receipt exists' do
    complete_origin_qualification
    first = execute_native_project.attributes
    account.disable_features!('jrc_projects')
    expect { execute_native_project }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingActionExecution.where(account: account).sole.attributes).to eq(first)
    expect(destination_effects).to eq([1, 1, 1])
  end

  it 'keeps a call-end draft without effects until the original agent explicitly confirms its reason' do
    revise_execution_rule('timing' => 'call_end')
    activate_execution_rule
    origin
    JrcContactCenter::QualificationDraft.new(account: account, member: member).save!(
      qualification, { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification)
    )
    expect { execute_native_project }.to raise_error(JrcContactCenter::OperationError, 'ending_action_trigger_pending')
    expect(destination_effects).to eq([0, 0, 0])
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'executes a confirmed call-end action without completing or discarding the independent ACW' do
    revise_execution_rule('timing' => 'call_end')
    activate_execution_rule
    origin
    JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
      qualification,
      attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
    )
    expect(execute_native_project.trigger_kind).to eq('ending_reason_confirmation')
    expect(destination_effects).to eq([1, 1, 1])
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingActionCompletion.where(account: account, origin: origin)).to be_empty
  end

  it 'does not use a valid original source ID as authority in another account' do
    complete_origin_qualification
    other = create(:account)
    other.enable_features!('jrc_contact_center', 'jrc_projects')
    expect { execute_native_project(origin.id, other) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'permanently blocks pending effects after deactivation and reactivation' do
    complete_origin_qualification
    revise_execution_rule('active' => false)
    revise_execution_rule('active' => true)
    activate_execution_rule
    expect { execute_native_project }.to raise_error(JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked')
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'preserves a successful fact instead of recreating a task removed from the destination' do
    complete_origin_qualification
    first = execute_native_project.attributes
    JrcProjects::Task.where(account: account).sole.destroy!
    expect(execute_native_project.attributes).to eq(first)
    expect(destination_effects).to eq([0, 1, 1])
  end

  it 'rejects updates and deletion of a committed success at the actual PostgreSQL boundary' do
    complete_origin_qualification
    identifier = execute_native_project.id
    statements = ["UPDATE jrc_contact_center_ending_action_executions SET target_id=0 WHERE id=#{identifier}",
                  "DELETE FROM jrc_contact_center_ending_action_executions WHERE id=#{identifier}"]
    statements.each do |statement|
      expect { ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(statement) } }
        .to raise_error(ActiveRecord::StatementInvalid, /Ending destination successes are immutable/)
    end
    expect(destination_effects).to eq([1, 1, 1])
  end

  it 'rolls back a real task and audit when PostgreSQL rejects its receipt, then safely retries' do
    complete_origin_qualification
    connection = ApplicationRecord.connection
    connection.execute(<<~SQL.squish)
      ALTER TABLE jrc_contact_center_ending_action_executions ADD CONSTRAINT cc_synthetic_receipt_failure
        CHECK (account_id <> #{account.id})
    SQL
    begin
      expect { execute_native_project }.to raise_error(ActiveRecord::StatementInvalid, /cc_synthetic_receipt_failure/)
      expect(destination_effects).to eq([0, 0, 0])
    ensure
      connection.execute('ALTER TABLE jrc_contact_center_ending_action_executions DROP CONSTRAINT cc_synthetic_receipt_failure')
    end
    expect(execute_native_project).to be_persisted
    expect(destination_effects).to eq([1, 1, 1])
  end

  it 'serializes two real independent workers into one native effect and one immutable receipt' do
    complete_origin_qualification
    state = { ready: Queue.new, result: Queue.new }
    workers = []
    account.with_lock do
      2.times do
        workers << waiting_executor(state)
        wait_for_executor_lock(state)
      end
    end
    results = Array.new(2) { Timeout.timeout(20) { state[:result].pop } }
    expect(results).to all(be_a(JrcContactCenter::EndingActionExecution))
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(destination_effects).to eq([1, 1, 1])
  ensure
    join_executors(workers || [])
  end

  it 'observes a committed destination-feature revocation while its worker is waiting for authority' do
    complete_origin_qualification
    state = { ready: Queue.new, result: Queue.new }
    workers = []
    account.with_lock do
      workers << waiting_executor(state)
      wait_for_executor_lock(state)
      account.disable_features!('jrc_projects')
    end
    expect(Timeout.timeout(20) { state[:result].pop }).to be_a(ActiveRecord::RecordNotFound)
    expect(destination_effects).to eq([0, 0, 0])
  ensure
    join_executors(workers || [])
  end

  it 'wraps the real effect with bounded immutable original-actor metadata and preserves the native result' do
    complete_origin_qualification
    observed = nil
    result = JrcContactCenter::EndingActions::ExecuteProjectTask.new(
      account: account, origin_id: origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE'
    ).call do |metadata, &effect|
      observed = metadata
      effect.call
    end
    expect(result).to be_a(JrcContactCenter::EndingActionExecution)
    expect(observed).to eq(account_id: account.id, origin_id: origin.id, version_id: origin.version_id,
                           actor_account_user_id: member.id, actor_user_id: actor.id, readiness_id: result.readiness_id,
                           rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task')
    expect(observed).to be_frozen
    expect(observed.fetch(:rule_code)).to be_frozen
    expect(observed.to_json).not_to include('SYNTHETIC unarmed original evidence', 'private_origin_evidence', 'private_definition')
    expect(destination_effects).to eq([1, 1, 1])
  end

  it 'leaves no native task or success when a trusted attempt writer fails before invoking the effect' do
    complete_origin_qualification
    command = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: origin.id,
                                                                      rule_code: 'SYNTHETIC_ORIGIN_RULE')
    expect { command.call { raise 'SYNTHETIC attempt-start failure' } }.to raise_error(RuntimeError, 'SYNTHETIC attempt-start failure')
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'rolls back the real native task and success if recording its attempt result fails' do
    complete_origin_qualification
    command = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: origin.id,
                                                                      rule_code: 'SYNTHETIC_ORIGIN_RULE')
    expect do
      command.call do |_metadata, &effect|
        effect.call
        raise 'SYNTHETIC attempt-result failure'
      end
    end.to raise_error(RuntimeError, 'SYNTHETIC attempt-result failure')
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'does not retain an earlier attempt callback when the same command is called normally again' do
    complete_origin_qualification
    command = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: origin.id,
                                                                      rule_code: 'SYNTHETIC_ORIGIN_RULE')
    expect { command.call { raise 'SYNTHETIC one callback only' } }.to raise_error(RuntimeError, 'SYNTHETIC one callback only')
    expect(command.call).to be_persisted
    expect(destination_effects).to eq([1, 1, 1])
  end

  it 'does not let attempt metadata mutation redirect the actual source or rule' do
    complete_origin_qualification
    command = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: origin.id,
                                                                      rule_code: 'SYNTHETIC_ORIGIN_RULE')
    expect { command.call { |metadata| metadata[:origin_id] = 0 } }.to raise_error(FrozenError)
    expect(destination_effects).to eq([0, 0, 0])
  end

  it 'still creates only one real native effect when the trusted wrapper accidentally invokes it twice' do
    complete_origin_qualification
    command = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: origin.id,
                                                                      rule_code: 'SYNTHETIC_ORIGIN_RULE')
    ids = []
    result = command.call do |_metadata, &effect|
      first = effect.call
      second = effect.call
      ids = [first.id, second.id]
      second
    end
    expect(ids).to eq([result.id, result.id])
    expect(destination_effects).to eq([1, 1, 1])
  end
end
