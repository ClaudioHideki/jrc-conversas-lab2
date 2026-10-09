# frozen_string_literal: true

class JrcServiceDesk::CreateApprovalService < JrcServiceDesk::BaseService
  def call(ticket_id:, attributes:, idempotency_key:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[title description due_at waiting_transition] + JrcServiceDesk::ApprovalTarget::FIELDS)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(values)
    with_ticket(ticket_id, :show?) do |ticket|
      raise Pundit::NotAuthorizedError unless context.capability?(:approvals_request)

      prior = authorized_replay(ticket, key, fingerprint)
      next prior if prior

      row = build_approval(ticket, values)
      deadline = JrcServiceDesk::OperationalRuleVersion.current(account_id: ticket.account_id, unit_id: ticket.unit_id, kind: 'approval_deadline')
      row.deadline_rule_version = deadline if deadline&.enabled?
      row.assign_attributes(idempotency_key: key, request_fingerprint: fingerprint)
      authorize!(row, :create?)
      row.save!
      append_event!(ticket, 'approval_requested', 'approval_id' => row.id)
      apply_waiting_transition(ticket, values['waiting_transition'], row) if values['waiting_transition']
      row
    end
  end

  private

  def authorized_replay(ticket, key, fingerprint)
    prior = ticket.ticket_approvals.find_by(requested_by_membership_id: actor_membership.id, idempotency_key: key)
    return unless prior

    authorize!(prior, :show?)
    raise JrcServiceDesk::IdempotencyConflict unless prior.request_fingerprint == fingerprint

    prior
  end

  def build_approval(ticket, values)
    target = JrcServiceDesk::ApprovalTarget.new(context: context, unit: ticket.unit).attributes(values)
    ticket.ticket_approvals.new(
      account: context.account, unit: ticket.unit, requested_by_membership: actor_membership,
      title: values.fetch('title'), description: values['description'], due_at: Time.iso8601(values.fetch('due_at')), **target
    )
  end

  def apply_waiting_transition(ticket, values, approval)
    values = JrcServiceDesk::Input.attributes(values, JrcServiceDesk::LifecycleTransitionService::FIELDS - %w[expected_lock_version])
    version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
    rule = version&.rules&.rule(values.fetch('rule_key'))
    raise ArgumentError, 'Approval waiting must use a published pause transition' unless rule && rule['action'] == 'pause'

    JrcServiceDesk::LifecycleTransitionService.new(user_context: context.to_h).call(
      ticket_id: ticket.id, attributes: values.merge('expected_lock_version' => ticket.lock_version),
      idempotency_key: "approval:#{approval.id}:waiting"
    )
  end
end
