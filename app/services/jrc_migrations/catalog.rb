module JrcMigrations::Catalog
  COMMON = %w[legacy_id created_at updated_at].freeze
  FILE_FIELDS = (COMMON + %w[filename content_type file_base64 file_sha256 file_size]).freeze
  FIELDS = {
    'companies' => COMMON + %w[name trade_name tax_id domain email phone_number website description person_kind relationship_type
                               owner_id parent_company_id legacy_parent_id],
    'contacts' => COMMON + %w[name last_name middle_name email phone_number identifier company_id company_legacy_id
                              registration_status contact_type],
    'projects' => COMMON + %w[key name description owner_id status visibility priority starts_on due_on archived_at completed_at
                              contact_id contact_legacy_id company_id company_legacy_id accepted_by_id acceptance_notes],
    'project_tasks' => COMMON + %w[project_id project_legacy_id parent_id parent_legacy_id title description status priority
                                   created_by_id assignee_id board_column_id estimated_minutes starts_on due_on labels],
    'service_desk_tickets' => COMMON + %w[unit_id requester_id requester_legacy_id company_id company_legacy_id title description
                                          status_id priority_id category_id queue_id team_id assignee_membership_id created_by_membership_id
                                          origin_channel opened_at idempotency_key request_fingerprint service_id ticket_type_id subcategory_id
                                          contract_id incident_id lifecycle_policy_version_id service_fields
                                          catalogue_snapshot impact_code urgency_code],
    'service_desk_events' => COMMON + %w[unit_id ticket_id ticket_legacy_id actor_membership_id event_type data
                                         correlation_id visibility audience_team_id],
    'service_desk_sla_snapshots' => COMMON + %w[unit_id ticket_id ticket_legacy_id version source_system source_reference source_version
                                                policy_key policy_version calendar_key calendar_version calendar_scope timezone
                                                contract_conditions policy_conditions calendar_conditions captured_at applied_at payload_digest],
    'service_desk_sla_milestones' => COMMON + %w[unit_id ticket_id ticket_legacy_id sla_snapshot_id sla_snapshot_legacy_id kind
                                                 due_at calculated_at calculator_version achieved_at],
    'project_attachments' => FILE_FIELDS + %w[project_id project_legacy_id],
    'project_task_attachments' => FILE_FIELDS + %w[task_id task_legacy_id]
  }.freeze
  ADAPTERS = {
    'companies' => 'Company', 'contacts' => 'Contact', 'projects' => 'Project', 'project_tasks' => 'ProjectTask',
    'service_desk_tickets' => 'ServiceDeskTicket', 'service_desk_events' => 'ServiceDeskEvent',
    'service_desk_sla_snapshots' => 'ServiceDeskSlaSnapshot', 'service_desk_sla_milestones' => 'ServiceDeskSlaMilestone',
    'project_attachments' => 'ProjectAttachment', 'project_task_attachments' => 'ProjectTaskAttachment'
  }.freeze

  def self.adapter(domain, account:, source:)
    name = ADAPTERS[domain]
    raise JrcMigrations::Error, 'UNSUPPORTED_DOMAIN' unless name

    "JrcMigrations::Adapters::#{name}".constantize.new(account: account, source: source)
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(canonical(value.as_json).to_json)
  end

  def self.canonical(value)
    case value
    when Hash then value.keys.sort.index_with { |key| canonical(value[key]) }
    when Array then value.map { |entry| canonical(entry) }
    else value
    end
  end
end
