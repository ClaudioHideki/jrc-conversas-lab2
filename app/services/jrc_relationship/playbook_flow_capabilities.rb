class JrcRelationship::PlaybookFlowCapabilities
  def self.call(reference)
    ([reference.policy.reason] + dispatch_dependencies(reference) +
      reference.flow.graph.fetch('nodes').filter_map { |node| node_dependency(reference, node) }).compact.uniq
  end

  def self.dispatch_dependencies(reference)
    flow = reference.flow
    reasons = []
    reasons << 'remote_flow_simulator_and_relationship_guard_unavailable' if flow.connection_id
    reasons << 'workflow_relationship_continuation_guard_required' if flow.engine != 'native'
    reasons << 'native_manual_trigger_required' unless flow.settings['trigger'] == 'manual'
    reasons.concat(keyword_dependencies(reference)) if flow.settings['keyword'].present?
    reasons << 'playbook_flow_outside_calendar' unless JrcFlows::BusinessHours.open?(flow.settings)
    reasons
  end

  def self.keyword_dependencies(reference)
    return ['native_message_keyword_input_required'] unless reference.input_message
    return [] if reference.input_message.content.to_s.downcase.include?(reference.flow.settings.fetch('keyword').downcase)

    ['playbook_flow_keyword_not_matched']
  end

  def self.node_dependency(reference, node)
    type = node.fetch('type')
    if JrcRelationship::PlaybookFlowPolicy::MUTATIONS.key?(type)
      return "playbook_flow_effect_not_approved:#{type}" unless reference.policy.effect_allowed?(type)

      JrcRelationship::PlaybookFlowMutationGuard.new(reference).authorize!(type, node.fetch('data'))
      return
    end
    if JrcRelationship::PlaybookFlowPolicy::DELIVERY_EFFECTS.include?(type)
      JrcRelationship::PlaybookFlowDeliveryGuard.new(reference).authorize!(type, node.fetch('data'))
      return
    end
    return "playbook_flow_effect_not_approved:#{type}" if %w[note message].include?(type) && !reference.policy.effect_allowed?(type)
    return if JrcRelationship::PlaybookFlow::INTERNAL_NODES.include?(type)

    reason = %w[media webhook nico].include?(type) ? 'native_relationship_delivery_guard_required' : 'native_relationship_action_grants_required'
    "#{reason}:#{type}"
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
    "native_relationship_action_grants_required:#{type}"
  end
end
