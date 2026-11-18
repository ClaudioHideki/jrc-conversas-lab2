# Reauthorize the persisted local snapshot; provider metadata is never catalog authority.
class JrcContactCenter::PauseDefinitionSnapshot
  def self.call(event:, member:, memberships:)
    return unless authorized?(event, member)

    definition = definition(event, member)
    return unless definition

    native = JrcContactCenter::AgentStateSnapshot.new(account_user: member).memberships
    units = native.where(id: memberships.select(:id)).joins(:queue).distinct.pluck('jrc_contact_center_queues.unit_id')
    return unless JrcContactCenter::PauseReasonDefinition.applicable?(definition, member: member, unit_ids: units)

    private_payload(event)
  end

  def self.private_payload(event)
    payload = event.metadata.fetch('pause_definition').slice(
      'code', 'name', 'category', 'description', 'revision', 'version', *JrcContactCenter::PauseReasonDefinition::TIMES,
      *JrcContactCenter::PauseReasonDefinition::OPTIONAL_FIELDS
    )
    justification = event.metadata['pause_justification']
    if justification.is_a?(String) && justification.length.between?(1, JrcContactCenter::AgentStateManager::JUSTIFICATION_LIMIT)
      payload['justification'] = justification
    end
    payload
  end

  def self.authorized?(event, member)
    return false unless event&.account_id == member.account_id && event.account_user_id == member.id

    context = { account: member.account, account_user: member, user: member.user }
    JrcContactCenter::ModulePolicy.new(context, :contact_center).operate? && local_operator_event?(event)
  end

  def self.definition(event, member)
    value = event.metadata['pause_definition']
    return unless valid_stamp?(value)

    definition = value.slice(*JrcContactCenter::PauseReasonDefinition::ALL_FIELDS).merge('active' => true)
    validator = JrcContactCenter::PauseReasonDefinition.new(account: member.account)
    definition if validator.call(definition, verify_references: false) == definition
  rescue JrcContactCenter::PauseReasonDefinition::Invalid
    nil
  end

  def self.valid_stamp?(value)
    value.is_a?(Hash) && value['revision'].is_a?(String) && value['revision'].match?(/\A[a-f0-9]{64}\z/) &&
      value['version'].is_a?(Integer) && value['version'].positive?
  end

  def self.local_operator_event?(event)
    event.source == JrcContactCenter::AgentStateManager::LOCAL_SOURCE && event.external_event_id.to_s.start_with?('operator:') &&
      event.metadata.is_a?(Hash) && event.metadata['provider_confirmed'] == false &&
      event.metadata['request_digest'].is_a?(String) && event.metadata['request_digest'].match?(/\A[a-f0-9]{64}\z/)
  end
  private_class_method :private_payload, :authorized?, :definition, :valid_stamp?, :local_operator_event?
end
