# frozen_string_literal: true

require_relative 'jrc_call_center_ending_attempt_upgrade'

# Owned synthetic preparation only. Reuse the native v1 fixtures and preserve
# an actual completed v1 Task/audit/success/attempt/outcome through the additive
# typed migration. No former call acquires a new typed attempt or permission.
class JrcContactCenter::SyntheticTypedDestinationUpgrade < JrcContactCenter::SyntheticEndingAttemptUpgrade
  DATABASE = 'jrc_cc_typed_destination_upgrade_synthetic'
  BEFORE = '/tmp/call-center-typed-destination-before.json'
  AFTER = '/tmp/call-center-typed-destination-upgrade.json'
  TABLES = %w[jrc_contact_center_ending_destination_consents jrc_contact_center_ending_destination_attempts
              jrc_contact_center_ending_destination_executions jrc_contact_center_ending_destination_outcomes].freeze

  def prepare
    guard!(installed: false)
    create_identity
    @account.update!(name: 'SYNTHETIC typed destination upgrade')
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @member, user: @member.user) do
      create_configuration
      activate_rule
      create_attendance
      create_existing_task
    end
    create_existing_success
    create_existing_attempt
    proof = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, account_id: @account.id, records: records.map { |row| snapshot(row) } }
    File.write(BEFORE, JSON.pretty_generate(proof))
  end

  def verify
    guard!(installed: true)
    before = load_typed_baseline!
    before.fetch('records').each { |row| verify_record!(row) }
    require Rails.root.join('db/migrate/20261125060000_create_contact_center_typed_destinations')
    CreateContactCenterTypedDestinations.new.up
    before.fetch('records').each { |row| verify_record!(row) }
    verify_empty_typed_history!
    result = { sha: before.fetch('sha'), synthetic: true, preserved_records: before.fetch('records'),
               exact_old_columns_and_values_preserved: true, existing_tasks_preserved: 2, successful_v1_receipts_preserved: 1,
               completed_v1_attempts_preserved: 1, completed_v1_outcomes_preserved: 1, typed_rows: 0,
               operational_effects_delta: 0, rerun_idempotent: true }
    File.write(AFTER, JSON.pretty_generate(result))
    result
  end

  private

  def guard!(installed:)
    config = ApplicationRecord.connection_db_config
    owned = runner_owned? && config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASE &&
            ApplicationRecord.connection.current_database == DATABASE && !ApplicationRecord.connection.transaction_open?
    raise 'Exclusive committed typed destination upgrade database required' unless owned
    expected = TABLES.all? { |table| ApplicationRecord.connection.table_exists?(table) == installed }
    raise 'Unexpected typed destination installation stage' unless expected

    native = %w[jrc_contact_center_ending_action_attempts jrc_contact_center_ending_action_attempt_outcomes]
    raise 'Native v1 attempt and outcome schemas required' unless native.all? { |table| ApplicationRecord.connection.table_exists?(table) }

    ActiveJob::Base.queue_adapter = :test
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def create_existing_attempt
    @legacy_attempt = JrcContactCenter::EndingActions::QueueProjectAttempt.new(
      account: @account, origin_id: @origin.id, rule_code: 'SYNTHETIC_UPGRADE_RULE', request_key: SecureRandom.uuid
    ).call
    @legacy_outcome = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: @account, attempt_id: @legacy_attempt.id).call
    raise 'Synthetic legacy success required' unless @legacy_outcome.outcome == 'succeeded' && @legacy_outcome.execution_id == @execution.id
  end

  def records
    super + [@legacy_attempt, @legacy_outcome]
  end

  def verify_record!(row)
    model = case row.fetch('type')
            when 'JrcContactCenter::EndingActionAttempt' then JrcContactCenter::EndingActionAttempt
            when 'JrcContactCenter::EndingActionAttemptOutcome' then JrcContactCenter::EndingActionAttemptOutcome
            end
    return super unless model

    actual = model.where(account: @account).find(row.fetch('id'))
    raise 'Original native v1 attempt or outcome changed' unless snapshot(actual).stringify_keys == row
  end

  def load_typed_baseline!
    before = JSON.parse(File.read(BEFORE))
    valid = before.fetch('sha') == ENV.fetch('GITHUB_SHA') && before.fetch('synthetic') == true
    raise 'Typed destination upgrade source identity mismatch' unless valid

    @account = Account.find(before.fetch('account_id'))
    raise 'Synthetic typed destination account required' unless @account.name == 'SYNTHETIC typed destination upgrade'

    before
  end

  def verify_empty_typed_history!
    counts = TABLES.map { |table| ApplicationRecord.connection.select_value("SELECT count(*) FROM #{table}").to_i }
    raise 'Installation cannot invent typed history' unless counts.all?(&:zero?)

    expected = [[JrcProjects::Task, 2], [JrcContactCenter::EndingActionExecution, 1],
                [JrcContactCenter::EndingActionAttempt, 1], [JrcContactCenter::EndingActionAttemptOutcome, 1]]
    raise 'Installation changed native v1 effects or history' unless expected.all? { |model, count| model.where(account: @account).count == count }
  end
end
