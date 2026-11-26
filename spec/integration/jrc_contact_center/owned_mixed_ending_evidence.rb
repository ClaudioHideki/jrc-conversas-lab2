# frozen_string_literal: true

require_relative 'owned_public_ending_queue'

# Read-only native evidence, except the explicit removal of this fixture's own failure constraint.
# Never starts a worker, calls a job directly, invents an ACK, or changes business records.
class SyntheticMixedEndingEvidence
  MARKER = 'jrc_cc_owned_mixed_ending'

  def self.context!(identifier)
    configuration = SyntheticPublicEndingQueue.configuration!
    raise 'Exact owned mixed account required' unless configuration.fetch('account_ids').include?(identifier)

    account = Account.find(identifier)
    marker = account.custom_attributes.fetch(MARKER)
    raise 'Current immutable source required' unless marker.fetch('source_sha') == configuration.fetch('source_sha')

    origin = JrcContactCenter::EndingActionOrigin.where(account: account).find(marker.fetch('origin_id'))
    raise 'Owned mixed qualification mismatch' unless origin.source_qualification_id == marker.fetch('qualification_id')

    verify_corporate_scope!(account, marker, origin)
    [account, marker, origin, configuration]
  end

  def self.verify_corporate_scope!(account, marker, origin)
    user = account.account_users.find(origin.actor_account_user_id).user
    scopes = account.jrc_crm_user_business_units.where(user: user).order(:id)
                    .pluck(:scope, :company_id, :business_unit_id, :active, :structure_managed, :team_id)
    current = Digest::SHA256.hexdigest(JSON.generate(scopes))
    raise 'The witness must preserve original corporate scope' unless current == marker.fetch('corporate_scope_before_sha256')
  end

  def self.attempts(account, origin)
    JrcContactCenter::EndingDestinationAttempt.where(account: account, origin: origin, rule_code: 'SYNTHETIC_MIXED_CRM_SD')
                                              .includes(:outcome, :execution).order(:id)
  end

  def self.allow_selected_retry!(identifier)
    account, marker, origin, = context!(identifier)
    crm, sd = failed_pair!(account, origin)
    name = marker.fetch('constraint')
    raise 'Own constraint identity required' unless name == "cc_public_mixed_sd_#{Integer(account.id)}"

    ApplicationRecord.connection.remove_check_constraint(:jrc_contact_center_ending_destination_executions, name: name)
    { source_sha: configuration_sha(account), account_id: account.id, own_failure_removed: true,
      successful_CRM_attempt_preserved: crm.id, failed_SD_attempt_preserved: sd.id, business_records_changed: false }
  end

  def self.failed_pair!(account, origin)
    rows = attempts(account, origin).to_a
    raise 'Exactly two original mixed attempts required' unless rows.length == 2

    crm = rows.select { |row| row.destination_kind == 'crm' }.sole
    sd = rows.select { |row| row.destination_kind == 'service_desk' }.sole
    require_rolled_back_pair!(account, crm, sd)
    [crm, sd]
  end

  def self.require_rolled_back_pair!(account, crm, service_desk)
    valid = crm.outcome&.outcome == 'succeeded' && service_desk.outcome&.outcome == 'failed'
    valid &&= service_desk.execution.nil? && JrcServiceDesk::Ticket.where(account: account).none?
    raise 'Actual independent CRM success and rolled-back Service Desk failure required' unless valid
  end

  def self.configuration_sha(account)
    account.custom_attributes.fetch(MARKER).fetch('source_sha')
  end

  def self.read(identifier)
    account, marker, origin, configuration = context!(identifier)
    rows = attempts(account, origin).to_a
    lead = existing_lead!(account, marker)
    validate_native_targets!(account, origin, marker, rows.filter_map(&:execution))
    qualification = JrcContactCenter::Qualification.where(account: account).find(origin.source_qualification_id)
    identity = origin_identity(account, origin, qualification)
    identity.merge(native_counts(account, lead)).merge(
      source_sha: configuration.fetch('source_sha'), original_corporate_unit_scope_preserved: true,
      existing_unit_mapped_Lead_unchanged: true, ACW_completed: qualification.completed_at.present?,
      attempts: rows.map { |row| present(row) }, real_worker: actual_worker_receipts(account, configuration, origin, rows),
      external_provider_operations: false
    )
  end

  def self.existing_lead!(account, marker)
    lead = account.jrc_crm_leads.find(marker.fetch('lead_id'))
    unchanged = Digest::SHA256.hexdigest(JSON.generate(lead.attributes)) == marker.fetch('lead_before')
    raise 'Existing native scoped Lead was changed or duplicated' unless unchanged && account.jrc_crm_leads.count == 1

    lead
  end

  def self.origin_identity(account, origin, qualification)
    { account_id: account.id, origin_id: origin.id, qualification_id: qualification.id,
      original_operator_user_id: origin.actor_user_id,
      original_actor_role: account.account_users.find(origin.actor_account_user_id).role }
  end

  def self.native_counts(account, lead)
    { native_lead_count: 1, existing_lead_id: lead.id, native_ticket_count: JrcServiceDesk::Ticket.where(account: account).count,
      native_Project_task_count_preserved: JrcProjects::Task.where(account: account).count }
  end

  def self.validate_native_targets!(account, origin, marker, targets)
    targets.each do |execution|
      if execution.destination_kind == 'crm'
        verify_native_lead!(execution, marker)
      else
        verify_native_ticket!(account, origin, execution)
      end
    end
  end

  def self.verify_native_lead!(execution, marker)
    valid = execution.target_type == 'JrcCrm::Lead' && execution.target_id == marker.fetch('lead_id')
    raise 'Only the existing authorized native Lead may be reused' unless valid
  end

  def self.verify_native_ticket!(account, origin, execution)
    raise 'Only native Service Desk is expected beside CRM' unless execution.destination_kind == 'service_desk'

    ticket = JrcServiceDesk::Ticket.where(account: account).find(execution.target_id)
    creator = JrcServiceDesk::UnitMembership.where(account: account).find(ticket.created_by_membership_id)
    original_actor = creator.account_user_id == origin.actor_account_user_id
    raise 'Original native Service Desk actor required' unless execution.target_type == ticket.class.name && original_actor

    raise 'Exactly one native creation event required' unless ticket.ticket_events.where(event_type: 'ticket_created').count == 1
  end

  def self.present(row)
    { id: row.id, request_id: row.request_key, version_id: row.version_id, destination_kind: row.destination_kind,
      retry_of_id: row.retry_of_id, effect_key: row.effect_key, outcome: row.outcome&.outcome,
      result_code: row.outcome&.result_code, execution_id: row.execution&.id,
      target_type: row.execution&.target_type, target_id: row.execution&.target_id }
  end

  def self.actual_worker_receipts(account, configuration, origin, rows)
    redis = Redis.new(url: ENV.fetch('REDIS_URL'))
    receipts = %w[produced acks].index_with do |kind|
      redis.hgetall("jrc_cc_public:#{configuration.fetch('nonce')}:#{kind}").transform_values { |raw| JSON.parse(raw) }
           .select { |_jid, row| row.fetch('account_id') == account.id }
    end
    produced, acks = receipts.values_at('produced', 'acks')
    raise 'Actual independent worker acknowledgements required' if produced.empty? || produced.keys.sort != acks.keys.sort

    verify_worker_rows!(produced, acks, configuration)
    verify_current_origin_jobs!(produced, origin, rows)
    { produced: produced, acknowledgements: acks, current_origin_dequeued: true,
      current_qualification_id: origin.source_qualification_id, destination_attempt_ids: rows.map(&:id) }
  end

  def self.verify_current_origin_jobs!(produced, origin, rows)
    jobs = produced.values
    qualification = jobs.any? do |row|
      row.fetch('job_class') == 'JrcContactCenter::EndingActionsJob' && row.fetch('record_id') == origin.source_qualification_id
    end
    raise 'The current mixed qualification must be dequeued, not only an earlier Project job' unless qualification

    ids = jobs.select { |row| row.fetch('job_class') == 'JrcContactCenter::EndingDestinationJob' }.pluck('record_id')
    raise 'Each current mixed destination attempt must have an actual dequeue' unless (rows.map(&:id) - ids).empty?
  end

  def self.verify_worker_rows!(produced, acks, configuration)
    producer_sha = Digest::SHA256.file(Rails.root.join('spec/integration/jrc_contact_center/owned_public_ending_adapter.rb')).hexdigest
    worker_sha = Digest::SHA256.file(Rails.root.join('spec/integration/jrc_contact_center/owned_public_ending_worker_boot.rb')).hexdigest
    produced.each do |jid, input|
      output = acks.fetch(jid)
      identity = %w[jid job_class account_id record_id source_sha queue]
      raise 'Actual producer/dequeue identity mismatch' unless input.slice(*identity) == output.slice(*identity)

      valid = input.fetch('witness_sha256') == producer_sha && output.fetch('witness_sha256') == worker_sha
      raise 'Native isolated PostgreSQL/Redis worker evidence missing' unless valid

      verify_worker_context!(output, configuration)
      verify_worker_processes!(input, output)
    end
  end

  def self.verify_worker_context!(output, configuration)
    valid = output.fetch('source_sha') == configuration.fetch('source_sha') && output.fetch('queue') == configuration.fetch('queue')
    valid &&= SyntheticPublicEndingQueue::JOB_CLASSES.include?(output.fetch('job_class'))
    valid &&= output.fetch('database') == SyntheticPublicEndingQueue::DATABASE && output.fetch('redis_database') == 15
    raise 'Native isolated PostgreSQL/Redis worker evidence missing' unless valid
  end

  def self.verify_worker_processes!(input, output)
    valid = output.fetch('postgres_backend_pid').positive? && output.fetch('worker_pid').positive?
    valid &&= input.fetch('producer_pid').positive? && input.fetch('producer_pid') != output.fetch('worker_pid')
    raise 'Native isolated PostgreSQL/Redis worker evidence missing' unless valid
  end
end
