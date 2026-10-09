# frozen_string_literal: true

class JrcServiceDesk::OperationalResourceService < JrcServiceDesk::BaseService
  TRANSITIONS = {
    'change' => { 'requested' => %w[planned cancelled], 'planned' => %w[approved cancelled],
                  'approved' => %w[in_progress cancelled], 'in_progress' => %w[completed cancelled] },
    'asset' => { 'active' => %w[inactive retired], 'inactive' => %w[active retired] }
  }.freeze

  def create(unit_id:, attributes:, idempotency_key:)
    values = JrcServiceDesk::OperationalResourceInput.call(attributes, creating: true)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(JrcServiceDesk::RecordedChanges.call(values))
    with_unit(unit_id) do |unit|
      existing_resource(unit, key, fingerprint) || create_resource(unit, values, key, fingerprint)
    end
  end

  def update(unit_id:, resource_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::OperationalResourceInput.call(attributes, creating: false)
    with_resource(unit_id, resource_id, :update?) do |row, unit|
      verify_version!(row, expected_lock_version)
      raise ArgumentError, 'Terminal resource history is preserved' if %w[completed cancelled retired].include?(row.state)

      verify_transition!(row, values['state']) if values['state'] && values['state'] != row.state

      assign_attributes(row, unit, values)
      next row unless row.changed? || values['ticket_ids']

      row.history += [entry('updated', values)]
      row.save!
      link!(row, values.fetch('ticket_ids', []))
      record_ticket_history(row, 'resource_updated')
      row
    end
  end

  def archive(unit_id:, resource_id:, expected_lock_version:)
    with_resource(unit_id, resource_id, :destroy?) do |row, _unit|
      verify_version!(row, expected_lock_version)
      target = row.resource_kind == 'asset' ? 'retired' : 'cancelled'
      verify_transition!(row, target)
      row.update!(state: target, history: row.history + [entry('archived', 'state' => target)])
      record_ticket_history(row, 'resource_archived')
      row
    end
  end

  private

  def existing_resource(unit, key, fingerprint)
    row = JrcServiceDesk::OperationalResource.find_by(account: context.account, unit: unit,
                                                      created_by_membership: actor_membership, idempotency_key: key)
    return unless row

    authorize!(row, :show?)
    raise JrcServiceDesk::IdempotencyConflict unless row.request_fingerprint == fingerprint

    row
  end

  def create_resource(unit, values, key, fingerprint)
    row = JrcServiceDesk::OperationalResource.new(account: context.account, unit: unit,
                                                  created_by_membership: actor_membership, idempotency_key: key, request_fingerprint: fingerprint)
    authorize!(row, :create?)
    initial = values['resource_kind'] == 'asset' ? 'active' : 'requested'
    raise ArgumentError, 'Resources must begin in their native initial state' if values['state'] && values['state'] != initial

    assign_attributes(row, unit, values.merge('state' => initial))
    row.history = [entry('created', values)]
    row.save!
    link!(row, values.fetch('ticket_ids', []))
    row
  end

  def with_resource(unit_id, id, query)
    with_unit(unit_id) do |unit|
      row = JrcServiceDesk::OperationalResource.where(account: context.account, unit: unit).lock.find(JrcServiceDesk::Input.id(id))
      authorize!(row, query)
      yield row, unit
    end
  end

  def assign_attributes(row, unit, values)
    row.assign_attributes(values.except('owner_account_user_id', 'company_id', 'approval_id', 'ticket_ids'))
    row.owner_membership = assignee(values['owner_account_user_id'], unit) if values.key?('owner_account_user_id')
    row.company = company(values['company_id']) if values.key?('company_id')
    row.approval = approval(values['approval_id'], unit) if values.key?('approval_id')
  end

  def company(value)
    return unless value

    allowed = context.account.feature_enabled?('jrc_customer_master') &&
              JrcCustomers::DirectoryPolicy.new(context.to_h, :directory).access?
    raise Pundit::NotAuthorizedError unless allowed

    JrcCustomers::Company.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(value))
  end

  def approval(value, unit)
    return unless value

    row = JrcServiceDesk::TicketApproval.where(account_id: context.account.id, unit: unit).find(JrcServiceDesk::Input.id(value))
    authorize!(row, :show?)
    row
  end

  def verify_transition!(row, target)
    allowed = TRANSITIONS.fetch(row.resource_kind).fetch(row.state, [])
    raise ArgumentError, 'Resource transition is not allowed' unless allowed.include?(target)
  end

  def link!(row, values)
    raise ArgumentError, 'Explicit ticket ID list required' unless values.is_a?(Array) && values.size <= 200

    values.map { |id| JrcServiceDesk::Input.id(id) }.uniq.sort.each { |id| link_ticket!(row, id) }
  end

  def link_ticket!(row, id)
    ticket = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: row.unit_id).lock.find(id)
    authorize!(ticket, :update?)
    return if row.resource_ticket_links.exists?(ticket: ticket)

    row.resource_ticket_links.create!(account: context.account, unit: row.unit, ticket: ticket, linked_by_membership: actor_membership)
    append_event!(ticket, 'resource_linked', 'resource_id' => row.id, 'resource_kind' => row.resource_kind)
  end

  def entry(action, values)
    { 'action' => action, 'actor_membership_id' => actor_membership.id, 'occurred_at' => Time.current.iso8601(6),
      'attributes' => JrcServiceDesk::RecordedChanges.call(values) }
  end

  def record_ticket_history(row, type)
    visible = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve
    visible.where(id: row.resource_ticket_links.select(:ticket_id)).find_each do |ticket|
      append_event!(ticket, type, 'resource_id' => row.id, 'resource_kind' => row.resource_kind, 'history_index' => row.history.size - 1)
    end
  end
end
