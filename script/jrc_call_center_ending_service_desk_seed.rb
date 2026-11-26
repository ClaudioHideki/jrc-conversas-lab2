# frozen_string_literal: true

# Only the existing owned disposable browser seed calls this fixture. No policy
# or membership is installed in a real Account; no Ticket is created here.
class JrcContactCenter::SyntheticEndingServiceDeskSeed
  PERMISSIONS = %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_tickets_create
                   jrc_service_desk_lookups_view jrc_service_desk_customers_view].freeze

  def self.call(account:, admin:, queue:)
    new(account: account, admin: admin, queue: queue).call
  end

  def initialize(account:, admin:, queue:)
    @account = account
    @admin = admin
    @queue = queue
  end

  def call
    self.class.verify_disposable_environment!
    verify_owned!
    data = JrcContactCenter::SyntheticEndingAutomationSeed.call(account: @account, admin: @admin, queue: @queue)
    @account.enable_features!('jrc_service_desk')
    @admin.custom_role.update!(permissions: (@admin.custom_role.permissions + PERMISSIONS).uniq)
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @admin, user: @admin.user) do
      unit = native_unit!
      references = native_references!(unit)
      map_source!(unit)
      data.merge(references).merge(service_desk_unit_id: unit.id.to_s, service_desk_unit_name: unit.name)
    end
  end

  def self.verify_disposable_environment!
    config = ApplicationRecord.connection_db_config
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Owned Service Desk configuration fixture required' unless owned
  end

  def self.evidence(identifier)
    verify_disposable_environment!
    account = Account.find(identifier)
    owned = account.name.start_with?('SYNTHETIC ') && account.custom_attributes['jrc_cc_sd_fixture_sha'] == ENV.fetch('GITHUB_SHA')
    raise 'Own current synthetic Service Desk account required' unless owned

    version_evidence(account).merge(
      source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id.to_s,
      tickets: JrcServiceDesk::Ticket.where(account: account).count,
      task_effects: JrcProjects::Task.where(account: account).count,
      attempts: JrcContactCenter::EndingDestinationAttempt.where(account: account).count
    )
  end

  def self.version_evidence(account)
    versions = JrcContactCenter::EndingActionVersion.where(account: account).order(:id)
    { version_ids: versions.map { |row| row.id.to_s },
      private_version_hashes: versions.to_h { |row| [row.id.to_s, Digest::SHA256.hexdigest(JSON.generate(row.private_definition))] } }
  end

  private

  def verify_owned!
    raise 'Owned synthetic Service Desk account required' unless @account.name.start_with?('SYNTHETIC ')
    raise 'Owned fixture identities required' unless [@admin.account_id, @queue.account_id].all?(@account.id)

    @account.update!(custom_attributes: @account.custom_attributes.merge('jrc_cc_sd_fixture_sha' => ENV.fetch('GITHUB_SHA')))
  end

  def native_unit!
    company = JrcServiceDesk::OperatorCompany.create!(account: @account, code: 'SYNTHETIC-SD', name: 'SYNTHETIC SD operator', active: true)
    unit = JrcServiceDesk::Unit.create!(
      account: @account, operator_company: company, code: 'SYNTHETIC-SD', name: 'SYNTHETIC mapped Service Desk unit', active: true
    )
    JrcServiceDesk::UnitMembership.create!(account: @account, unit: unit, account_user: @admin, active: true)
    unit
  end

  def native_references!(unit)
    status = JrcServiceDesk::TicketStatus.create!(
      account: @account, unit: unit, code: 'SYNTHETIC-OPEN', name: 'SYNTHETIC initial open', active: true,
      phase: 'open', initial: true, position: 0
    )
    priority = JrcServiceDesk::Priority.create!(
      account: @account, unit: unit, code: 'SYNTHETIC-PRIORITY', name: 'SYNTHETIC reviewed priority', active: true, position: 1
    )
    { service_desk_status_id: status.id.to_s, service_desk_priority_id: priority.id.to_s, service_desk_priority_name: priority.name }
  end

  def map_source!(unit)
    scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(revision: :desc).first!
    business = @account.jrc_crm_business_units.find(scope.business_unit_id)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => unit.id.to_s))
  end
end
