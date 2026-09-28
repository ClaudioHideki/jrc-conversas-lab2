# frozen_string_literal: true

class JrcServiceDesk::LifecycleTransitionService < JrcServiceDesk::BaseService
  FIELDS = %w[rule_key expected_lock_version expected_policy_version_id reason_code note solution evidence_note_ids fields].freeze

  def call(ticket_id:, attributes:, idempotency_key:)
    data = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    expected = JrcServiceDesk::Input.version(data.fetch('expected_lock_version'))
    expected_policy = JrcServiceDesk::Input.id(data.fetch('expected_policy_version_id'))
    normalized = normalize(data)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(normalized)
    with_ticket(ticket_id, :show?) do |ticket|
      Pundit.authorize(context.to_h, ticket, :apply?, policy_class: JrcServiceDesk::LifecycleActionPolicy)
      if JrcServiceDesk::HistoryProjection.protected_input?(normalized) && !JrcServiceDesk::TicketPolicy.new(context.to_h, ticket).view_notes?
        raise Pundit::NotAuthorizedError, 'Protected lifecycle content requires note visibility'
      end
      prior = ticket.lifecycle_transitions.find_by(actor_membership_id: actor_membership.id, request_key: key)
      if prior
        raise Pundit::NotAuthorizedError unless JrcServiceDesk::LifecycleActionPolicy.new(context.to_h, ticket).action?(prior.action)
        raise JrcServiceDesk::IdempotencyConflict, 'Transition key reused for different input' unless prior.fingerprint == fingerprint
        next prior
      end
      verify_version!(ticket, expected)
      version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
      raise Pundit::NotAuthorizedError, 'No applicable lifecycle policy' unless version
      raise JrcServiceDesk::IdempotencyConflict, 'Policy selection changed; reload' unless version.id == expected_policy
      rule = version.rules.rule(normalized.fetch('rule_key'))
      raise Pundit::NotAuthorizedError unless JrcServiceDesk::LifecycleActionPolicy.new(context.to_h, ticket).action?(rule.fetch('action'))
      unless JrcServiceDesk::LifecycleActionPolicy.new(context.to_h, ticket).requirements_allowed?(rule.fetch('requirements'))
        raise Pundit::NotAuthorizedError, 'Required lifecycle evidence is outside the permitted content scope'
      end
      now = Time.current
      target = validate_transition!(ticket, version, rule)
      version.rules.validate_payload!(rule, normalized, classified: ticket.category_id.present?)
      verify_evidence!(ticket, normalized['evidence_note_ids'])
      reason = rule['action'] == 'pause' ? version.rules.reason(normalized['reason_code'], target.id) : nil
      raise ArgumentError, 'Reason only applies to pause' if rule['action'] != 'pause' && normalized['reason_code']
      reopening = if rule['action'] == 'reopen'
                    anchor_action = version.definition.fetch('reopen').fetch('anchor_action')
                    anchor = ticket.lifecycle_transitions.where(action: anchor_action).order(occurred_at: :desc, id: :desc).first
                    version.rules.reopen_check!(now: now, anchor: anchor&.occurred_at)
                  end
      unless ticket.lifecycle_policy_version_id
        ticket.lifecycle_policy_version = version
        ticket.save!
        append_event!(ticket, 'lifecycle_policy_bound', 'policy_version_id' => version.id, 'version' => version.version, 'digest' => version.digest)
      end
      sla = JrcServiceDesk::LifecycleClocks.new(ticket: ticket, version: version, actor: actor_membership, now: now)
        .run!(rule: rule, reason: reason, reopening: reopening)
      previous = ticket.status
      ticket.status = target
      ticket.save!
      transition = ticket.lifecycle_transitions.create!(account: context.account, unit: ticket.unit,
        lifecycle_policy_version: version, actor_membership: actor_membership, from_status: previous, to_status: target,
        action: rule['action'], rule_key: rule['key'], request_key: key, fingerprint: fingerprint, occurred_at: now,
        payload: normalized.except('expected_lock_version', 'expected_policy_version_id').merge(
          'from_phase' => previous.phase, 'to_phase' => target.phase, 'policy_digest' => version.digest,
          'policy_version' => version.version, 'sla' => sla))
      append_event!(ticket, 'lifecycle_transitioned', 'transition_id' => transition.id, 'action' => transition.action,
        'from_status_id' => previous.id, 'to_status_id' => target.id, 'policy_version_id' => version.id,
        'policy_version' => version.version, 'cycle_id' => sla['cycle_id'])
      transition
    end
  end

  private

  def normalize(data)
    result = JrcServiceDesk::CanonicalJson.normalize(data)
    result['expected_lock_version'] = JrcServiceDesk::Input.version(result.fetch('expected_lock_version'))
    result['expected_policy_version_id'] = JrcServiceDesk::Input.id(result.fetch('expected_policy_version_id'))
    result['evidence_note_ids'] ||= []
    raise ArgumentError unless result['evidence_note_ids'].is_a?(Array)
    result['evidence_note_ids'] = result['evidence_note_ids'].map { |id| JrcServiceDesk::Input.id(id) }
    result['fields'] ||= {}
    result
  end

  def validate_transition!(ticket, version, rule)
    raise ArgumentError, 'Transition not allowed from current status' unless rule['from_status_ids'].include?(ticket.status_id)
    target = reference(JrcServiceDesk::TicketStatus, rule.fetch('to_status_id'), ticket.unit)
    [ticket.status, target].each do |status|
      raise ArgumentError, 'Status semantics changed since policy publication' unless version.status_phases[status.id.to_s] == status.phase && status.active?
    end
    target
  end

  def verify_evidence!(ticket, ids)
    ids.each do |id|
      note = ticket.ticket_notes.where(account_id: context.account.id, unit_id: ticket.unit_id).find(id)
      authorize!(note, :show?)
    end
  end
end
