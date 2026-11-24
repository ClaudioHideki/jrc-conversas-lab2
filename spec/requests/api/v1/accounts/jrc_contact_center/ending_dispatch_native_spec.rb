require 'rails_helper'
require 'timeout'
require 'stringio'

# Actual native commits, ActiveJob entry points and PostgreSQL destinations.
# Only the explicit broker-failure example replaces enqueueing, never the task,
# authorization, readiness, success receipt or attempt/outcome persistence.
RSpec.describe 'Native committed ending events and operational Projects dispatch' do
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable committed ending dispatch database required' unless owned
    raise 'Committed ending dispatch fixtures required' if ApplicationRecord.connection.transaction_open?

    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous_adapter if previous_adapter
  end

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  before do
    activate_dispatch_rule
    clear_enqueued_jobs
    clear_performed_jobs
  end

  def activate_dispatch_rule
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: SecureRandom.uuid,
                                                    expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def revise_dispatch_rule(changes)
    project = JrcProjects::Project.where(account: account).sole
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member,
                                                       input: origin_rule_document(project).merge(changes),
                                                      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def dispatch_effects
    [JrcProjects::Task.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
     JrcContactCenter::EndingActionExecution.where(account: account).count,
     JrcContactCenter::EndingActionAttempt.where(account: account).count,
     JrcContactCenter::EndingActionAttemptOutcome.where(account: account).count]
  end

  def dispatch_committed_qualification
    JrcContactCenter::EndingActionsJob.perform_now(account.id, qualification.id)
  end

  def waiting_dispatch_worker(state)
    ids = [account.id, qualification.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:results] << JrcContactCenter::EndingActionsJob.new.perform(*ids)
      end
    rescue StandardError => error
      state[:results] << error
    end
  end

  def wait_for_dispatch_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
  end

  it 'executes a real completed ACW through its native after-commit hook and ActiveJob worker' do
    perform_enqueued_jobs(only: JrcContactCenter::EndingActionsJob) { complete_origin_qualification }
    expect(qualification.reload.completed_at).to be_present
    expect(dispatch_effects).to eq([1, 1, 1, 1, 1])
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole.outcome).to eq('succeeded')
  end

  it 'uses the database-attested confirmation source and leaves ACW open for an actual call-end automation' do
    revise_dispatch_rule('timing' => 'call_end')
    activate_dispatch_rule
    origin
    perform_enqueued_jobs(only: JrcContactCenter::EndingActionsJob) do
      JrcContactCenter::ConfirmEndingReason.new(account: account, member: member).call(
        qualification, attributes: { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
        expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification), request_key: SecureRandom.uuid
      )
    end
    expect(dispatch_effects).to eq([1, 1, 1, 1, 1])
    expect(qualification.reload.completed_at).to be_nil
    expect(JrcContactCenter::EndingActionExecution.where(account: account).sole.trigger_kind).to eq('ending_reason_confirmation')
  end

  it 'does not enqueue or execute an ACW completion rolled back by the actual native transaction' do
    origin
    Account.transaction do
      complete_origin_qualification
      raise ActiveRecord::Rollback
    end
    expect(enqueued_jobs.count { |job| job[:job] == JrcContactCenter::EndingActionsJob }).to eq(0)
    expect(qualification.reload.completed_at).to be_nil
    expect(dispatch_effects).to eq([0, 0, 0, 0, 0])
  end

  it 'does not dispatch a mutable ending draft as a confirmed classification' do
    revise_dispatch_rule('timing' => 'call_end')
    activate_dispatch_rule
    origin
    JrcContactCenter::QualificationDraft.new(account: account, member: member).save!(
      qualification, { reason_code: 'SYNTHETIC_ORIGIN_REASON' },
      expected_revision: JrcContactCenter::QualificationDraftRevision.token(qualification)
    )
    dispatch_committed_qualification
    expect(dispatch_effects).to eq([0, 0, 0, 0, 0])
    expect(qualification.reload.completed_at).to be_nil
  end

  it 'keeps repeated committed event delivery on one initial attempt and one native Task' do
    complete_origin_qualification
    3.times { dispatch_committed_qualification }
    expect(dispatch_effects).to eq([1, 1, 1, 1, 1])
  end

  it 'records a destination revoked after the native event as blocked without administrative substitution' do
    complete_origin_qualification
    account.disable_features!('jrc_projects')
    dispatch_committed_qualification
    expect(dispatch_effects).to eq([0, 0, 0, 1, 1])
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole.result_code).to eq('reference_unavailable')
  end

  it 'does not revive an old blocked attempt when destination access later returns' do
    complete_origin_qualification
    account.disable_features!('jrc_projects')
    dispatch_committed_qualification
    original = JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole.attributes
    account.enable_features!('jrc_projects')
    dispatch_committed_qualification
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole.attributes).to eq(original)
    expect(dispatch_effects).to eq([0, 0, 0, 1, 1])
  end

  it 'does not execute a deactivated old original after the rule is reactivated' do
    complete_origin_qualification
    revise_dispatch_rule('active' => false)
    revise_dispatch_rule('active' => true)
    activate_dispatch_rule
    dispatch_committed_qualification
    expect(dispatch_effects).to eq([0, 0, 0, 0, 0])
  end

  it 'does not treat an explicit agent-confirmation mode as automatic execution' do
    revise_dispatch_rule('execution_mode' => 'agent_confirmation')
    activate_dispatch_rule
    complete_origin_qualification
    dispatch_committed_qualification
    expect(dispatch_effects).to eq([0, 0, 0, 0, 0])
  end

  it 'preserves completed ACW and durable pending work when the enqueue broker fails and recovers without duplication' do
    output = StringIO.new
    previous_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)
    allow(JrcContactCenter::EndingActionsJob).to receive(:perform_later).and_raise(ActiveJob::EnqueueError, 'SYNTHETIC_PRIVATE_BROKER_PAYLOAD')
    complete_origin_qualification
    expect(qualification.reload.completed_at).to be_present
    expect(dispatch_effects).to eq([0, 0, 0, 1, 0])
    expect(output.string).to include('ending_automation_enqueue_unavailable')
    expect(output.string).not_to include('SYNTHETIC_PRIVATE_BROKER_PAYLOAD')
    JrcContactCenter::EndingAttemptReconcileJob.perform_now(account.id)
    JrcContactCenter::EndingAttemptReconcileJob.perform_now(account.id)
    expect(dispatch_effects).to eq([1, 1, 1, 1, 1])
  ensure
    Rails.logger = previous_logger
  end

  it 'does not use a qualification belonging to another account as a dispatch source' do
    complete_origin_qualification
    other = create(:account)
    other.enable_features!('jrc_contact_center')
    expect(JrcContactCenter::EndingActionsJob.perform_now(other.id, qualification.id)).to eq(0)
    expect(JrcContactCenter::EndingActionAttempt.where(account: other)).to be_empty
    expect(dispatch_effects).to eq([0, 0, 0, 0, 0])
  end

  it 'keeps the original non-administrator agent through actual event dispatch under a configuration manager context' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      JrcContactCenter::EndingActionsJob.perform_now(account.id, original.source_qualification_id)
      expect(Current.account_user.id).to eq(member.id)
    end
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(operator.user_id)
    expect(JrcContactCenter::EndingActionExecution.where(account: account).sole.actor_account_user_id).to eq(operator.id)
    expect(dispatch_effects).to eq([1, 1, 1, 1, 1])
  end

  it 'does not enqueue another automation when an unrelated field of an already completed qualification changes' do
    complete_origin_qualification
    clear_enqueued_jobs
    qualification.reload.update!(notes: 'SYNTHETIC later note')
    expect(enqueued_jobs.count { |job| job[:job] == JrcContactCenter::EndingActionsJob }).to eq(0)
    expect(dispatch_effects).to eq([0, 0, 0, 0, 0])
  end

  it 'serializes two actual event workers without duplicating initial work, destination records or outcomes' do
    complete_origin_qualification
    states = Array.new(2) { { ready: ::Queue.new, results: ::Queue.new } }
    workers = []
    begin
      account.with_lock do
        states.each do |state|
          workers << waiting_dispatch_worker(state)
          wait_for_dispatch_lock(state)
        end
      end
    ensure
      workers.each do |worker|
        worker.join(20)
        raise 'Synthetic dispatch worker remained active' if worker.alive?
      end
    end
    expect(states.map { |state| Timeout.timeout(8) { state[:results].pop } }).to eq([1, 1])
    expect(dispatch_effects).to eq([1, 1, 1, 1, 1])
  end
end
