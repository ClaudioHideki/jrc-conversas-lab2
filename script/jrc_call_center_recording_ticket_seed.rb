# frozen_string_literal: true

# Used only by the existing explicitly owned recordings seed. All rights below
# belong to synthetic actors; no real account, provider or automation is enabled.
class JrcContactCenter::SyntheticRecordingTicketSeed
  MARKER = 'jrc_cc_owned_recording_ticket'
  RIGHTS = %w[jrc_service_desk_module_view jrc_service_desk_tickets_view jrc_service_desk_tickets_create
              jrc_service_desk_lookups_view jrc_service_desk_customers_view].freeze

  def self.call(account:, operator:, queue:)
    owned!(account, operator, queue)
    account.enable_features!('jrc_service_desk')
    operator.custom_role.update!(permissions: (operator.custom_role.permissions + RIGHTS).uniq)
    company = JrcServiceDesk::OperatorCompany.create!(account: account, code: 'SYNTHETIC-REC', name: 'SYNTHETIC recording SD operator', active: true)
    unit = JrcServiceDesk::Unit.create!(account: account, operator_company: company, code: 'SYNTHETIC-REC',
                                      name: 'SYNTHETIC recording Service Desk', active: true)
    JrcServiceDesk::UnitMembership.create!(account: account, unit: unit, account_user: operator, active: true)
    references = references!(account, unit)
    business = account.jrc_crm_business_units.find(JrcServiceDesk::Input.id(queue.unit.settings.fetch('business_unit_id')))
    raise 'Exact owned issuer required' unless business.company_id == JrcServiceDesk::Input.id(queue.unit.settings.fetch('issuer_company_id'))

    business.update!(settings: business.settings.merge('service_desk_unit_id' => unit.id.to_s))
    account.reload.update!(settings: account.settings.merge(MARKER => {
      'source_sha' => ENV.fetch('GITHUB_SHA'), 'unit_id' => unit.id, 'account_user_id' => operator.id
    }))
    references.merge(unit_id: unit.id.to_s, unit_name: unit.name)
  end

  def self.references!(account, unit)
    status = JrcServiceDesk::TicketStatus.create!(account: account, unit: unit, code: 'SYNTHETIC-REC-OPEN',
                                                name: 'SYNTHETIC recording initial status', active: true, phase: 'open', initial: true, position: 0)
    priority = JrcServiceDesk::Priority.create!(account: account, unit: unit, code: 'SYNTHETIC-REC',
                                              name: 'SYNTHETIC recording reviewed priority', active: true, position: 1)
    { status_id: status.id.to_s, priority_id: priority.id.to_s, priority_name: priority.name }
  end

  def self.owned!(account, operator, queue)
    config = ApplicationRecord.connection_db_config
    runtime = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
              ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116' &&
              config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
              JrcContactCenter::SyntheticRecordingsSeed.owned_database?(config)
    raise 'Owned synthetic recording Ticket scope required' unless runtime

    marker = account.settings.fetch(JrcContactCenter::SyntheticRecordingsSeed::MARKER)
    owned = account.name.start_with?('SYNTHETIC pause ') && account.name.end_with?('-recordings') &&
            marker.fetch('source_sha') == ENV.fetch('GITHUB_SHA') && marker.fetch('record_ids').uniq.length == 24 &&
            operator.account_id == account.id && queue.account_id == account.id
    raise 'Exact owned recording Ticket identities required' unless owned
  end
  private_class_method :owned!, :references!
end
