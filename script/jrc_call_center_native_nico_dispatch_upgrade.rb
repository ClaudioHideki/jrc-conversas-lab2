# frozen_string_literal: true

require_relative 'jrc_call_center_ending_attempt_upgrade'

# Full native M20 baseline plus existing Helpdesk rows, before the new table.
# No migration or runner is started by loading this test helper.
class JrcContactCenter::SyntheticNicoDispatchUpgrade < JrcContactCenter::SyntheticEndingAttemptUpgrade
  DATABASE = 'jrc_cc_nico_intent_upgrade_synthetic'
  BEFORE = '/tmp/call-center-nico-dispatch-upgrade-before.json'
  AFTER = '/tmp/call-center-nico-dispatch-upgrade.json'
  TABLE = :jrc_nico_helpdesk_dispatch_intents
  NATIVE_TYPES = [JrcServiceDesk::OperatorCompany, JrcServiceDesk::Unit, JrcServiceDesk::UnitMembership,
                  JrcServiceDesk::TicketStatus, JrcServiceDesk::Priority, Contact, JrcCustomers::Company,
                  JrcServiceDesk::Ticket, JrcNico::Helpdesk::PolicyVersion, JrcNico::Helpdesk::Event].index_by(&:name).freeze

  def prepare
    guard!(installed: false)
    raise 'Native NICO upgrade already prepared' if File.exist?(BEFORE)

    create_identity
    @account.update!(name: 'SYNTHETIC native NICO intent upgrade')
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @member, user: @member.user) do
      create_configuration
      activate_rule
      create_attendance
      create_existing_task
      create_existing_success
      create_native_unit
      create_native_ticket
      create_legacy_nico_event
    end
    proof = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, account_id: @account.id, records: records.map { |row| snapshot(row) } }
    File.write(BEFORE, JSON.pretty_generate(proof))
  end

  def verify
    guard!(installed: true)
    baseline = JSON.parse(File.read(BEFORE))
    raise 'Native NICO upgrade identity mismatch' unless baseline.fetch('sha') == ENV.fetch('GITHUB_SHA') && baseline.fetch('synthetic') == true

    @account = Account.find(baseline.fetch('account_id'))
    raise 'Synthetic native NICO upgrade account required' unless @account.name == 'SYNTHETIC native NICO intent upgrade'

    baseline.fetch('records').each { |row| verify_record!(row) }
    verify_no_retroactive_delivery!
    JrcNico::Helpdesk::MonitorJob.perform_now
    baseline.fetch('records').each { |row| verify_record!(row) }
    verify_no_retroactive_delivery!
    result = { sha: ENV.fetch('GITHUB_SHA'), synthetic: true, preserved_records: baseline.fetch('records'),
               exact_old_columns_and_values_preserved: true, technical_intents: 0, existing_tasks: 2,
               existing_native_successes: 1, existing_tickets: 1, legacy_events: 1, provider_or_broker_execution: false }
    File.write(AFTER, JSON.pretty_generate(result))
    result
  end

  private

  def guard!(installed:)
    raise 'Exclusive committed native NICO upgrade database required' unless owned_database?
    raise 'Unexpected native NICO intent installation stage' unless ApplicationRecord.connection.table_exists?(TABLE) == installed
    raise 'Complete M20 source schema required' unless ApplicationRecord.connection.table_exists?(:jrc_contact_center_ending_action_attempts)

    ActiveJob::Base.queue_adapter = :test
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def owned_database?
    config = ApplicationRecord.connection_db_config
    runner_owned? && config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASE &&
      ApplicationRecord.connection.current_database == DATABASE && !ApplicationRecord.connection.transaction_open?
  end

  def create_native_unit
    @account.enable_features!('jrc_service_desk', 'jrc_customer_master')
    @sd_operator = JrcServiceDesk::OperatorCompany.create!(account: @account, code: 'SYNTHETIC_NICO', name: 'SYNTHETIC operator', active: true)
    @sd_unit = JrcServiceDesk::Unit.create!(account: @account, operator_company: @sd_operator, code: 'SYNTHETIC_NICO',
                                            name: 'SYNTHETIC native upgrade unit', active: true)
    @sd_membership = JrcServiceDesk::UnitMembership.create!(account: @account, unit: @sd_unit, account_user: @member, active: true)
    @sd_status = JrcServiceDesk::TicketStatus.create!(account: @account, unit: @sd_unit, code: 'SYNTHETIC_OPEN', name: 'SYNTHETIC open',
                                                      phase: 'open', initial: true, position: 0, active: true)
    @sd_priority = JrcServiceDesk::Priority.create!(account: @account, unit: @sd_unit, code: 'SYNTHETIC_NORMAL',
                                                    name: 'SYNTHETIC priority', position: 1, active: true)
  end

  def create_native_ticket
    @sd_company = @account.master_companies.create!(name: 'SYNTHETIC NICO upgrade customer')
    @sd_contact = @account.contacts.create!(name: 'SYNTHETIC NICO requester', company_id: @sd_company.id,
                                            email: "nico-upgrade-#{SecureRandom.hex(8)}@example.test")
    @sd_ticket = JrcServiceDesk::Ticket.create!(account: @account, unit: @sd_unit, requester: @sd_contact, company_id: @sd_company.id,
                                                title: 'SYNTHETIC existing native ticket', description: 'SYNTHETIC populated upgrade only',
                                                status: @sd_status, priority: @sd_priority, created_by_membership: @sd_membership,
                                                origin_channel: 'manual', opened_at: Time.current, idempotency_key: SecureRandom.uuid,
                                                request_fingerprint: JrcServiceDesk::CanonicalJson.digest('synthetic_upgrade' => true))
  end

  def create_legacy_nico_event
    @account.update!(custom_attributes: @account.custom_attributes.merge('nico_enabled' => true))
    definition = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [@sd_unit.id], 'company_ids' => [@sd_company.id],
                                                             'operator_ids' => [@member.id])
    definition['rules']['R16']['enabled'] = true
    @nico_policy = JrcNico::Helpdesk::PolicyVersion.create!(
      account: @account, author: @member, number: 1, state: 'published', enabled: true,
      published_at: Time.current, definition: definition, digest: JrcNico::Helpdesk::Definition.digest(definition)
    )
    @legacy_event = JrcNico::Helpdesk::Event.create!(account: @account, actor: @member, policy_version: @nico_policy, ticket: @sd_ticket,
                                                     rule_key: 'R16', correlation_key: "synthetic-legacy:#{SecureRandom.uuid}",
                                                     detected_at: Time.current)
  end

  def records
    super + [@sd_operator, @sd_unit, @sd_membership, @sd_status, @sd_priority, @sd_company, @sd_contact, @sd_ticket, @nico_policy, @legacy_event]
  end

  def verify_record!(row)
    type = row.fetch('type')
    return super unless NATIVE_TYPES.key?(type)

    actual = NATIVE_TYPES.fetch(type).where(account_id: @account.id).find(row.fetch('id'))
    raise 'Original native NICO upgrade record changed' unless snapshot(actual).stringify_keys == row
  end

  def verify_no_retroactive_delivery!
    raise 'Upgrade cannot backfill delivery intents' unless JrcNico::Helpdesk::DispatchIntent.count.zero?
    raise 'Upgrade changed Tasks' unless JrcProjects::Task.where(account: @account).count == 2
    raise 'Upgrade changed native successes' unless JrcContactCenter::EndingActionExecution.where(account: @account).count == 1
    raise 'Upgrade changed Tickets' unless JrcServiceDesk::Ticket.where(account: @account).count == 1
    raise 'Upgrade changed legacy NICO events' unless JrcNico::Helpdesk::Event.where(account: @account).count == 1

    count = ApplicationRecord.connection.select_value("SELECT COUNT(*) FROM schema_migrations WHERE version='20261124200000'")
    raise 'Native intent migration registry mismatch' unless count.to_i == 1
  end
end
