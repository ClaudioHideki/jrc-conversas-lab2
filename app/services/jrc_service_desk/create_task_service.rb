# frozen_string_literal: true

class JrcServiceDesk::CreateTaskService < JrcServiceDesk::BaseService
  FIELDS = %w[title description due_at priority assignee_account_user_id visibility audience_team_id checklist parent_task_id completion_policy].freeze

  def call(ticket_id:, attributes:, idempotency_key:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(values)
    audience = JrcServiceDesk::InteractionVisibility.attributes(values)
    with_ticket(ticket_id, :show?) do |ticket|
      JrcServiceDesk::InteractionVisibility.authorize_publication!(context, ticket, **audience, capability: :tasks_manage)
      previous = authorized_replay(ticket, key, fingerprint)
      next previous if previous

      policy = JrcServiceDesk::TaskCompletionPolicy.new(values.fetch('completion_policy', {}))
      policy.verify!(context, ticket, publishing: true)

      row = build_task(ticket, values, audience).tap do |task|
        task.idempotency_key = key
        task.request_fingerprint = fingerprint
        task.completion_policy = policy.definition
        task.completion_policy_digest = JrcServiceDesk::CanonicalJson.digest(policy.definition) unless policy.definition.empty?
      end
      authorize!(row, :create?)
      row.save!
      record_creation(ticket, row)
      row
    end
  end

  private

  def authorized_replay(ticket, key, fingerprint)
    previous = ticket.ticket_tasks.find_by(created_by_membership_id: actor_membership.id, idempotency_key: key)
    return unless previous

    authorize!(previous, :show?)
    raise JrcServiceDesk::IdempotencyConflict unless previous.request_fingerprint == fingerprint

    previous
  end

  def build_task(ticket, values, audience)
    ticket.ticket_tasks.new(
      account: context.account, unit: ticket.unit, created_by_membership: actor_membership,
      title: values.fetch('title'), description: values['description'], due_at: values['due_at'] && Time.iso8601(values['due_at']),
      priority: values.fetch('priority', 'normal'), assignee_membership: assignee(values['assignee_account_user_id'], ticket.unit),
      checklist: values.fetch('checklist', []), visibility: audience[:visibility], audience_team_id: audience[:audience_team_id],
      parent_task: parent_task(ticket, values['parent_task_id'])
    )
  end

  def record_creation(ticket, row)
    JrcServiceDesk::TicketEvent.create!(
      account: context.account, unit: ticket.unit, ticket: ticket, actor_membership: actor_membership,
      event_type: 'task_created', visibility: row.visibility, audience_team_id: row.audience_team_id,
      data: { 'task_id' => row.id, 'status' => row.status }
    )
  end

  def parent_task(ticket, value)
    return unless value

    ticket.ticket_tasks.lock.find(JrcServiceDesk::Input.id(value)).tap { |row| authorize!(row, :update?) }
  end
end
