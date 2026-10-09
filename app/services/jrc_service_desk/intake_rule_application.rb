# frozen_string_literal: true

# Runs inside the native creation unit transaction. Replay never reapplies rules.
class JrcServiceDesk::IntakeRuleApplication
  def initialize(ticket:, context:, supplied:, conversation: nil)
    @ticket = ticket
    @context = context
    @supplied = supplied
    @conversation = conversation
    @applied = {}
  end

  def apply!
    enabled = %w[routing priority_matrix sla_selection].any? do |kind|
      JrcServiceDesk::OperationalRuleVersion.current(account_id: @ticket.account_id, unit_id: @ticket.unit_id, kind: kind)&.enabled?
    end
    return unless enabled || @supplied['impact_code'] || @supplied['urgency_code']

    verify_conversation!
    apply_matrix!
    apply_route!
    @ticket.catalogue_snapshot = @ticket.catalogue_snapshot.merge('operational_rules' => @applied) if @applied.any?
  end

  def record_sla!
    selection = selected('sla_selection')
    return unless selection
    raise Pundit::NotAuthorizedError unless @context.capability?(:sla_snapshots_record)

    version, rule = selection
    attributes = rule.fetch('output').fetch('snapshot').merge('captured_at' => @ticket.opened_at.iso8601(6))
    snapshot = JrcServiceDesk::SlaSnapshot.new(attributes)
    bound_policy = @ticket.lifecycle_policy_version
    unless bound_policy && bound_policy.definition.dig('sla', 'mode') == 'calendar_snapshot'
      raise JrcServiceDesk::LifecycleDependencyError, 'A compatible published lifecycle policy is required'
    end

    JrcServiceDesk::LifecycleClocks.verify_snapshot!(snapshot, clock_kinds: bound_policy.rules.clock_kinds)
    created = JrcServiceDesk::RecordSlaSnapshotService.new(user_context: @context.to_h).call(ticket_id: @ticket.id, attributes: attributes)
    @ticket.ticket_events.create!(account: @ticket.account, unit: @ticket.unit,
                                  actor_membership: @ticket.created_by_membership, event_type: 'operational_rule_applied',
                                  data: { 'kind' => 'sla_selection', 'rule_version_id' => version.id, 'rule_key' => rule['key'],
                                          'rule_digest' => version.digest, 'snapshot_id' => created.id })
  rescue JrcServiceDesk::LifecycleDependencyError
    raise ArgumentError, 'Published intake SLA requires a compatible lifecycle and calendar'
  end

  private

  def verify_conversation!
    return unless @conversation

    @conversation = Conversation.where(account_id: @ticket.account_id).lock('FOR SHARE').find(@conversation.id)
    raise Pundit::NotAuthorizedError unless @context.capability?(:conversations_link) && @conversation.contact_id == @ticket.requester_id

    JrcServiceDesk::NativeExecutionContext.with(@context.to_h) { Pundit.authorize(@context.to_h, @conversation, :show?) }
    inbox = Inbox.where(account_id: @ticket.account_id).find(@conversation.inbox_id)
    JrcServiceDesk::NativeExecutionContext.with(@context.to_h) { Pundit.authorize(@context.to_h, inbox, :show?) }
  end

  def facts
    { 'inbox_id' => @conversation&.inbox_id, 'channel_type' => @conversation&.inbox&.channel_type,
      'company_id' => @ticket.company_id || @ticket.requester.company_id, 'contract_id' => @ticket.contract_id,
      'category_id' => @ticket.category_id, 'service_id' => @ticket.service_id, 'priority_id' => @ticket.priority_id,
      'ticket_type_id' => @ticket.ticket_type_id, 'impact' => @ticket.impact_code, 'urgency' => @ticket.urgency_code }
  end

  def selected(kind)
    version = JrcServiceDesk::OperationalRuleVersion.current(account_id: @ticket.account_id, unit_id: @ticket.unit_id, kind: kind)
    return unless version&.enabled?
    raise JrcServiceDesk::IdempotencyConflict, 'Rule digest mismatch' unless version.digest == version.expected_digest

    rule = JrcServiceDesk::OperationalRuleMatcher.call(version.definition.fetch('rules'), facts)
    return unless rule

    # Revalidate references of the matching rule, not unrelated private rules.
    validator = JrcServiceDesk::OperationalRuleReferences.new(context: @context, unit: @ticket.unit)
    validator.validate_facts!(rule.fetch('match'))
    validator.validate_facts!(rule.fetch('output'))
    [version, rule]
  end

  def apply_matrix!
    impact = @supplied['impact_code']
    urgency = @supplied['urgency_code']
    return if impact.nil? && urgency.nil?
    raise ArgumentError, 'Both impact and urgency required' unless impact && urgency

    [impact, urgency].each { |value| JrcServiceDesk::OperationalRuleContract.token!(value) }
    @ticket.impact_code = impact
    @ticket.urgency_code = urgency
    version, rule = selected('priority_matrix')
    raise ArgumentError, 'No published matching matrix entry' unless rule

    id = rule.fetch('output').fetch('priority_id')
    if @supplied['priority_id'] && JrcServiceDesk::Input.id(@supplied['priority_id']) != id
      raise JrcServiceDesk::IdempotencyConflict, 'Explicit priority disagrees with published matrix'
    end

    @ticket.priority = JrcServiceDesk::Priority.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, active: true).find(id)
    remember('priority_matrix', version, rule)
  end

  def apply_route!
    # Explicit assignment wins. Published channel routing precedes catalogue default.
    return if @supplied.values_at('queue_id', 'team_id', 'assignee_account_user_id').any?

    version, rule = selected('routing')
    return unless rule
    raise Pundit::NotAuthorizedError unless @context.capability?(:tickets_assign)

    @ticket.queue = JrcServiceDesk::Queue.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, active: true)
                                         .find(rule.fetch('output').fetch('queue_id'))
    @ticket.team = @ticket.queue.team
    Pundit.authorize(@context.to_h, @ticket.team, :show?) if @ticket.team
    # An explicit/default assignee may belong to another queue: do not silently move it.
    if @ticket.assignee_membership && @ticket.team &&
       !TeamMember.exists?(team_id: @ticket.team_id, user_id: @ticket.assignee_membership.account_user.user_id)
      raise JrcServiceDesk::IdempotencyConflict, 'Catalogue assignee is incompatible with channel routing'
    end

    remember('routing', version, rule)
  end

  def remember(kind, version, rule)
    @applied[kind] = { 'version_id' => version.id, 'version' => version.version, 'digest' => version.digest, 'key' => rule['key'] }
  end
end
