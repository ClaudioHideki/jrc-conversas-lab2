# frozen_string_literal: true

require_relative 'jrc_call_center_typed_destination_upgrade'

# Reuse established native legacy fixture builders, never their output paths or installation-stage assumptions.
class JrcContactCenter::SyntheticRecordingTaskUpgrade < JrcContactCenter::SyntheticTypedDestinationUpgrade
  DATABASE = 'jrc_cc_recording_task_upgrade_synthetic'
  BEFORE = '/tmp/call-center-recording-task-before.json'
  AFTER = '/tmp/call-center-recording-task-upgrade.json'
  HISTORY = 'jrc_contact_center_recording_task_links'

  def prepare
    guard!(installed: false)
    create_identity
    @account.update!(name: 'SYNTHETIC recording task upgrade')
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @member, user: @member.user) do
      create_configuration
      activate_rule
      create_attendance
      create_existing_task
    end
    create_existing_success
    create_existing_attempt
    @historical_record = old_record
    proof = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, account_id: @account.id, records: records.map { |row| snapshot(row) } }
    File.write(BEFORE, JSON.pretty_generate(proof))
  end

  def verify
    guard!(installed: true)
    before = baseline!
    before.fetch('records').each { |row| verify_record!(row) }
    require Rails.root.join('db/migrate/20261127003000_create_contact_center_recording_task_links')
    CreateContactCenterRecordingTaskLinks.new.up
    before.fetch('records').each { |row| verify_record!(row) }
    raise 'Migration cannot create task links' unless JrcContactCenter::RecordingTaskLink.count.zero?

    proof = { sha: before.fetch('sha'), synthetic: true, preserved_records: before.fetch('records'),
              exact_old_columns_and_values_preserved: true, existing_native_tasks: 2, existing_v1_successes: 1,
              recording_task_links: 0, automatic_grants_or_retroactive_work: false, rerun_idempotent: true }
    File.write(AFTER, JSON.pretty_generate(proof))
    proof
  end

  private

  def guard!(installed:)
    raise 'Exclusive committed recording task upgrade database required' unless database_owned?
    raise 'Unexpected recording task installation stage' unless ApplicationRecord.connection.table_exists?(HISTORY) == installed

    ActiveJob::Base.queue_adapter = :test
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def database_owned?
    config = ApplicationRecord.connection_db_config
    runner_owned? && config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASE &&
      ApplicationRecord.connection.current_database == DATABASE && !ApplicationRecord.connection.transaction_open?
  end

  def old_record
    TelephonyCallRecord.create!(account: @account, provider: Pabx::Settings::PROVIDER, external_tenant: '8', extension: '1410',
                                external_unique_id: 'SYNTHETIC-existing-quality-record', synced_at: Time.current,
                                started_at: 2.hours.ago, direction: 'inbound', status: 'answered', has_recording: true,
                                caller: '551100000001', callee: '1410', recording_reference: '/synthetic/private-old-recording.wav')
  end

  def records
    super + [@historical_record]
  end

  def verify_record!(row)
    return super unless row.fetch('type') == 'TelephonyCallRecord'

    actual = TelephonyCallRecord.where(account: @account).find(row.fetch('id'))
    raise 'Historical native recording changed during upgrade' unless snapshot(actual).stringify_keys == row
  end

  def baseline!
    before = JSON.parse(File.read(BEFORE))
    raise 'Quality upgrade source identity mismatch' unless before.fetch('sha') == ENV.fetch('GITHUB_SHA') && before.fetch('synthetic') == true

    @account = Account.find(before.fetch('account_id'))
    raise 'Owned synthetic recording task upgrade account required' unless @account.name == 'SYNTHETIC recording task upgrade'

    before
  end
end
