# frozen_string_literal: true

class JrcServiceDesk::CreateTicketService < JrcServiceDesk::BaseService
  FIELDS = %w[title description requester_id status_id priority_id category_id queue_id team_id assignee_account_user_id].freeze
  IDS = (FIELDS - %w[title description]).freeze

  def call(unit_id:, attributes:, idempotency_key:, service_id: nil)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    normalized = FIELDS.to_h { |name| [name, values[name]] }
    normalized['title'] = text(normalized['title'])
    normalized['description'] = text(normalized['description'], nullable: true)
    IDS.each { |name| normalized[name] = JrcServiceDesk::Input.id(normalized[name]) unless normalized[name].nil? }
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    service_id = JrcServiceDesk::Input.id(service_id) unless service_id.nil?
    fingerprint = JrcServiceDesk::CanonicalJson.digest(service_id ? normalized.merge('service_id' => service_id) : normalized)

    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)
      if normalized.values_at('assignee_account_user_id', 'queue_id', 'team_id').any?
        raise Pundit::NotAuthorizedError unless context.capability?(:tickets_assign)
      end
      existing = JrcServiceDesk::Ticket.find_by(account_id: context.account.id, unit_id: unit.id,
                                                 created_by_membership_id: actor_membership.id, idempotency_key: key)
      if existing
        raise Pundit::NotAuthorizedError unless context.capability?(:tickets_create)
        authorize!(existing, :show?)
        raise JrcServiceDesk::IdempotencyConflict, 'Idempotency key belongs to a different request' unless existing.request_fingerprint == fingerprint

        next existing
      end

      requester = Contact.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(normalized['requester_id']))
      authorize!(requester, :show?)
      queue = reference(JrcServiceDesk::Queue, normalized['queue_id'], unit)
      ticket = JrcServiceDesk::Ticket.new(
        account: context.account, unit: unit, title: normalized['title'], description: normalized['description'], requester: requester,
        status: reference(JrcServiceDesk::TicketStatus, normalized['status_id'], unit),
        priority: reference(JrcServiceDesk::Priority, normalized['priority_id'], unit),
        category: reference(JrcServiceDesk::Category, normalized['category_id'], unit), queue: queue,
        team: native_team(normalized['team_id'] || queue&.team_id),
        assignee_membership: assignee(normalized['assignee_account_user_id'], unit),
        created_by_membership: actor_membership, origin_channel: 'manual', opened_at: Time.current,
        idempotency_key: key, request_fingerprint: fingerprint
      )
      ticket.service = reference(JrcServiceDesk::Service, service_id, unit)
      ticket.lifecycle_policy_version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
      authorize!(ticket, :create?)
      ticket.save!
      if ticket.lifecycle_policy_version
        version = ticket.lifecycle_policy_version
        append_event!(ticket, 'lifecycle_policy_bound', 'policy_version_id' => version.id, 'version' => version.version, 'digest' => version.digest)
      end
      append_event!(ticket, 'ticket_created', ticket.attributes.slice('status_id', 'priority_id', 'queue_id', 'assignee_membership_id'))
      ticket
    end
  end
end
