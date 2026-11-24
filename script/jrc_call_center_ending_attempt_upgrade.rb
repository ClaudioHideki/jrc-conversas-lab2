# frozen_string_literal: true

require_relative 'jrc_call_center_ending_success_upgrade'

# Reuse the proven native M18 fixtures, adding an actual M19 Task/audit/success
# before M20 exists. The database, snapshots and verification remain exclusive.
class JrcContactCenter::SyntheticEndingAttemptUpgrade < JrcContactCenter::SyntheticEndingExecutionUpgrade
  DATABASE = 'jrc_cc_ending_attempt_upgrade_synthetic'
  BEFORE = '/tmp/call-center-ending-attempt-before.json'
  AFTER = '/tmp/call-center-ending-attempt-upgrade.json'

  def prepare
    guard!(installed: false)
    create_identity
    @account.update!(name: 'SYNTHETIC ending attempt upgrade')
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @member, user: @member.user) do
      create_configuration
      activate_rule
      create_attendance
      create_existing_task
      create_existing_success
    end
    proof = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, account_id: @account.id, records: records.map { |row| snapshot(row) } }
    File.write(BEFORE, JSON.pretty_generate(proof))
  end

  def verify
    guard!(installed: true)
    before = load_attempt_baseline!
    before.fetch('records').each { |row| verify_record!(row) }
    require Rails.root.join('db/migrate/20261124001000_create_contact_center_ending_action_attempts')
    CreateContactCenterEndingActionAttempts.new.up
    before.fetch('records').each { |row| verify_record!(row) }
    verify_empty_history!
    result = { sha: before.fetch('sha'), synthetic: true, preserved_records: before.fetch('records'),
               exact_old_columns_and_values_preserved: true, existing_tasks_preserved: 2, successful_receipts_preserved: 1,
               queued_attempts: 0, terminal_outcomes: 0, operational_effects_delta: 0, rerun_idempotent: true }
    File.write(AFTER, JSON.pretty_generate(result))
    result
  end

  private

  def guard!(installed:)
    raise 'Exclusive committed ending attempt upgrade database required' unless owned_upgrade_database?

    tables = %i[jrc_contact_center_ending_action_attempts jrc_contact_center_ending_action_attempt_outcomes]
    correct = tables.all? { |table| ApplicationRecord.connection.table_exists?(table) == installed }
    raise 'Unexpected ending attempt installation stage' unless correct
    raise 'Native M19 success schema required' unless ApplicationRecord.connection.table_exists?(:jrc_contact_center_ending_action_executions)

    ActiveJob::Base.queue_adapter = :test
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def owned_upgrade_database?
    config = ApplicationRecord.connection_db_config
    runner_owned? && config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASE &&
      ApplicationRecord.connection.current_database == DATABASE && !ApplicationRecord.connection.transaction_open?
  end

  def create_existing_success
    @execution = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: @account, origin_id: @origin.id,
                                                                         rule_code: 'SYNTHETIC_UPGRADE_RULE').call
    @automated_task = JrcProjects::Task.where(account: @account).find(@execution.target_id)
    @automated_audit = JrcProjects::AuditEvent.where(account: @account, auditable_type: @automated_task.class.name,
                                                     auditable_id: @automated_task.id, action: 'projects.task.created').sole
  end

  def records
    super + [@execution, @automated_task, @automated_audit]
  end

  def verify_record!(row)
    return super unless row.fetch('type') == 'JrcContactCenter::EndingActionExecution'

    actual = JrcContactCenter::EndingActionExecution.where(account: @account).find(row.fetch('id'))
    raise 'Original native success changed' unless snapshot(actual).stringify_keys == row
  end

  def load_attempt_baseline!
    before = JSON.parse(File.read(BEFORE))
    valid = before.fetch('sha') == ENV.fetch('GITHUB_SHA') && before.fetch('synthetic') == true
    raise 'Ending attempt upgrade source identity mismatch' unless valid

    @account = Account.find(before.fetch('account_id'))
    raise 'Synthetic ending attempt account required' unless @account.name == 'SYNTHETIC ending attempt upgrade'

    before
  end

  def verify_empty_history!
    empty = JrcContactCenter::EndingActionAttempt.count.zero? && JrcContactCenter::EndingActionAttemptOutcome.count.zero?
    raise 'Installation cannot queue old work or invent outcomes' unless empty
    raise 'Installation changed existing tasks' unless JrcProjects::Task.where(account: @account).count == 2
    raise 'Installation changed existing successes' unless JrcContactCenter::EndingActionExecution.where(account: @account).count == 1
  end
end
