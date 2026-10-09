# frozen_string_literal: true

class JrcServiceDesk::TaskCompletionPolicy
  FIELDS = %w[enabled lifecycle_policy_version_id lifecycle_policy_digest next_task approval transition].freeze
  attr_reader :definition

  def initialize(value)
    @definition = JrcServiceDesk::Input.attributes(value, FIELDS)
    return if definition.empty?

    raise ArgumentError, 'Explicit task progression switch required' unless [true, false].include?(definition['enabled'])

    return unless enabled?

    validate_publication!
    validate_effect_objects!
    validate_effects!
  end

  def enabled?
    definition['enabled'] == true
  end

  def verify!(context, ticket, publishing: false)
    return unless enabled?

    raise Pundit::NotAuthorizedError unless !publishing || context.capability?(:lifecycle_policies_manage)

    version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
    raise JrcServiceDesk::IdempotencyConflict, 'Task progression policy changed or was revoked' unless current_publication?(version)
  end

  private

  def validate_publication!
    raise ArgumentError, 'Complete published task progression required' unless definition.keys.sort == FIELDS.sort

    JrcServiceDesk::Input.id(definition['lifecycle_policy_version_id'])
    digest = definition['lifecycle_policy_digest']
    raise ArgumentError, 'Policy digest required' unless digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/)
  end

  def validate_effect_objects!
    %w[next_task approval transition].each do |key|
      raise ArgumentError, 'Explicit progression object required' unless definition[key].nil? || definition[key].is_a?(Hash)
    end
    raise ArgumentError, 'Task progression effect required' if %w[next_task approval transition].all? { |key| definition[key].nil? }
  end

  def current_publication?(version)
    return false unless version

    version.id == JrcServiceDesk::Input.id(definition['lifecycle_policy_version_id']) &&
      version.digest == definition['lifecycle_policy_digest'] && version.lifecycle_policy.current_version_id == version.id
  end

  def validate_effects!
    if definition['next_task']
      JrcServiceDesk::Input.attributes(definition['next_task'], JrcServiceDesk::CreateTaskService::FIELDS - %w[completion_policy])
    end
    if definition['approval']
      JrcServiceDesk::Input.attributes(definition['approval'], %w[title description due_at] + JrcServiceDesk::ApprovalTarget::FIELDS)
    end
    return unless definition['transition']

    allowed = JrcServiceDesk::LifecycleTransitionService::FIELDS - %w[expected_lock_version expected_policy_version_id]
    JrcServiceDesk::Input.attributes(definition['transition'], allowed)
  end
end
