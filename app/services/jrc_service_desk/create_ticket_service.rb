# frozen_string_literal: true

class JrcServiceDesk::CreateTicketService < JrcServiceDesk::BaseService
  FIELDS = %w[title description requester_id status_id priority_id category_id queue_id team_id assignee_account_user_id
              ticket_type_id subcategory_id contract_id impact_code urgency_code].freeze
  IDS = (FIELDS - %w[title description impact_code urgency_code]).freeze
  CLASSIFICATION_FIELDS = %w[ticket_type_id subcategory_id contract_id impact_code urgency_code].freeze

  def call(unit_id:, attributes:, idempotency_key:, service_id: nil, origin_channel: 'manual', intake_conversation: nil, internal_request: false)
    raise ArgumentError unless %w[manual portal].include?(origin_channel)

    with_unit(unit_id) do |unit|
      raise ArgumentError unless [true, false].include?(internal_request)
      raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)
      raise ArgumentError if internal_request && origin_channel != 'manual'

      fields = internal_request ? %w[title description service_fields] : creation_fields
      values = JrcServiceDesk::Input.attributes(attributes, fields)
      normalized = (FIELDS - CLASSIFICATION_FIELDS).index_with { |name| values[name] }
      normalized.merge!(values.slice(*CLASSIFICATION_FIELDS))
      normalized.merge!(JrcServiceDesk::InternalIntake.defaults!(unit, context)) if internal_request
      normalized['title'] = text(normalized['title'])
      normalized['description'] = text(normalized['description'], nullable: true)
      IDS.each { |name| normalized[name] = JrcServiceDesk::Input.id(normalized[name]) unless normalized[name].nil? }
      # Omitted/null company uses the historical fingerprint format for safe replay.
      normalize_company!(values, normalized)
      if values['establishment_company_id'].present?
        raise Pundit::NotAuthorizedError unless JrcServiceDesk::PortalRoutingConfiguration.read(unit)['stores_enabled'] == true
        normalized['establishment_company_id'] = JrcServiceDesk::Input.id(values['establishment_company_id'])
        JrcServiceDesk::RequesterDirectory.new(context).company!(normalized['establishment_company_id'])
      end
      key = JrcServiceDesk::Input.request_key(idempotency_key)
      service_id = JrcServiceDesk::Input.id(service_id) unless service_id.nil?
      normalized['service_fields'] = values['service_fields'] if values.key?('service_fields')
      fingerprint_values = service_id ? normalized.merge('service_id' => service_id) : normalized
      fingerprint_values = fingerprint_values.merge('origin_channel' => origin_channel) if origin_channel != 'manual'
      fingerprint_values = fingerprint_values.merge('internal_request' => true) if internal_request
      fingerprint = JrcServiceDesk::CanonicalJson.digest(fingerprint_values)

      raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)

      if normalized.values_at('assignee_account_user_id', 'queue_id', 'team_id').any?
        raise Pundit::NotAuthorizedError unless context.capability?(:tickets_assign)
      end
      existing = JrcServiceDesk::Ticket.find_by(account_id: context.account.id, unit_id: unit.id,
                                                created_by_membership_id: context.creator_memberships(unit), idempotency_key: key)
      if existing
        raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)

        authorize!(existing, :show?)
        raise JrcServiceDesk::IdempotencyConflict, 'Idempotency key belongs to a different request' unless existing.request_fingerprint == fingerprint

        next existing
      end

      requester = Contact.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(normalized['requester_id']))
      authorize!(requester, :show?)
      JrcServiceDesk::RequesterDirectory.new(context).validate!(requester, company_id: normalized['company_id'])
      apply_company_route!(unit, requester, values, normalized) if origin_channel == 'manual' && !internal_request
      service, queue = catalogue_references(service_id, normalized, unit, internal_request: internal_request)
      ticket = JrcServiceDesk::Ticket.new(
        account: context.account, unit: unit, title: normalized['title'], description: normalized['description'], requester: requester,
        status: reference(JrcServiceDesk::TicketStatus, normalized['status_id'], unit),
        priority: reference(JrcServiceDesk::Priority, normalized['priority_id'], unit),
        category: reference(JrcServiceDesk::Category, normalized['category_id'], unit), queue: queue,
        team: native_team(normalized['team_id'] || queue&.team_id),
        assignee_membership: assignee(normalized['assignee_account_user_id'], unit),
        created_by_membership: actor_membership, origin_channel: origin_channel, opened_at: Time.current,
        idempotency_key: key, request_fingerprint: fingerprint
      )
      if internal_request
        JrcServiceDesk::InternalIntake.apply!(ticket)
        ticket.assignee_membership = assignee(ticket.assignee_membership.account_user_id, unit)
        values.merge!('queue_id' => ticket.queue_id, 'team_id' => ticket.team_id,
                      'assignee_account_user_id' => ticket.assignee_membership.account_user_id)
      end
      configure_catalogue(ticket, service, normalized, values)
      JrcServiceDesk::TicketCatalogue.new(ticket, context: context).bind!(normalized)
      intake = JrcServiceDesk::IntakeRuleApplication.new(ticket: ticket, context: context, supplied: values, conversation: intake_conversation)
      intake.apply!
      if !internal_request && ticket.assignee_membership && normalized['assignee_account_user_id'].nil?
        reason = JrcServiceDesk::AssignmentEligibility.new(membership: ticket.assignee_membership, ticket: ticket).reason
        ticket.assignee_membership = nil if reason
      end
      verify_assignee_team!(ticket, manual: internal_request || normalized['assignee_account_user_id'].present?)
      raise Pundit::NotAuthorizedError unless context.supervision_access.allowed?(ticket, 'tickets_create')
      authorize!(ticket, :create?)
      ticket.save!
      if internal_request
        _, _, observer = JrcServiceDesk::InternalIntake.destinations(unit)
        observer_context = JrcServiceDesk::OperationalContext.new(account: unit.account, user: observer.account_user.user, account_user: observer.account_user)
        Pundit.authorize(observer_context.to_h, ticket, :show?)
        append_event!(ticket, 'resource_updated', 'internal_request' => true, 'observer_account_user_id' => observer.account_user_id)
      end
      intake.record_actions!
      intake.record_sla!
      if ticket.lifecycle_policy_version
        version = ticket.lifecycle_policy_version
        append_event!(ticket, 'lifecycle_policy_bound', 'policy_version_id' => version.id, 'version' => version.version, 'digest' => version.digest)
      end
      append_event!(ticket, 'ticket_created', ticket.attributes.slice('status_id', 'priority_id', 'queue_id', 'assignee_membership_id'))
      ticket
    end
  end

  private

  def apply_company_route!(unit, requester, values, normalized)
    return if normalized.values_at('queue_id', 'team_id', 'assignee_account_user_id').any?

    configuration = JrcServiceDesk::PortalRoutingConfiguration.read(unit).slice('company_routes')
    route = JrcServiceDesk::PortalRoutingConfiguration.resolve(unit: unit, context: context, values: configuration,
                                                              company_id: normalized['company_id'] || requester.company_id)
    normalized.merge!(route)
    values.merge!(route)
  end

  def normalize_company!(values, normalized)
    return if values['company_id'].blank?
    raise Pundit::NotAuthorizedError unless context.capability?(:customers_view)

    Pundit.authorize(context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
    normalized['company_id'] = JrcServiceDesk::Input.id(values['company_id'])
    JrcCustomers::Company.where(account_id: context.account.id).find(normalized['company_id'])
  end

  def creation_fields
    fields = FIELDS + ['service_fields']
    context.account.feature_enabled?('jrc_customer_master') ? fields + %w[company_id establishment_company_id] : fields
  end

  def catalogue_references(service_id, normalized, unit, internal_request: false)
    service = reference(JrcServiceDesk::Service, service_id, unit)
    queue = reference(JrcServiceDesk::Queue, normalized['queue_id'] || service&.default_queue_id, unit)
    raise Pundit::NotAuthorizedError if queue && !internal_request && !context.capability?(:tickets_assign)

    normalized['priority_id'] ||= service&.default_priority_id
    [service, queue]
  end

  def configure_catalogue(ticket, service, normalized, values)
    ticket.company_id = normalized['company_id'] if normalized.key?('company_id')
    ticket.establishment_company_id = normalized['establishment_company_id'] if normalized.key?('establishment_company_id')
    ticket.service_fields = values.fetch('service_fields', {})
    ticket.service = service
    ticket.lifecycle_policy_version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
  end
end
