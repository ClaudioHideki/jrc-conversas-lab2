class JrcRelationship::PlaybookFlowPolicy
  DEFAULTS = { 'phase' => 1, 'approved_phase' => 0, 'pilot_company_ids' => [], 'pilot_business_unit_ids' => [],
               'allow_unassigned_business_unit' => false, 'pilot_account_user_ids' => [], 'approval_required' => true,
               'approval_ttl_seconds' => 600, 'hourly_limit' => 10, 'max_steps' => 100, 'allowed_effects' => ['note'] }.freeze
  MUTATIONS = { 'status' => 'status', 'labels' => 'labels', 'assign' => 'assign', 'contact' => 'contact_update',
                'create_lead' => 'create_lead', 'activity' => 'activity', 'move_deal' => 'move_deal', 'nico' => 'nico' }.freeze
  DELIVERY_EFFECTS = %w[media webhook].freeze
  EFFECTS = (%w[note message] + MUTATIONS.values + DELIVERY_EFFECTS).freeze

  attr_reader :definition

  def initialize(reference)
    @reference = reference
    @definition = reference.configuration.effective_rules.fetch('playbook_flow_policy', DEFAULTS)
    self.class.validate!(definition)
  end

  def self.validate!(value)
    raise ArgumentError, 'Explicit flow policy required' unless value.is_a?(Hash) && value.keys.sort == DEFAULTS.keys.sort

    %w[pilot_company_ids pilot_business_unit_ids pilot_account_user_ids].each { |key| JrcNico::Helpdesk::Definition.ids!(value.fetch(key)) }
    %w[allow_unassigned_business_unit approval_required].each { |key| JrcNico::Helpdesk::Definition.boolean!(value.fetch(key)) }
    ranges = { 'phase' => 1..3, 'approved_phase' => 0..3, 'approval_ttl_seconds' => 30..900, 'hourly_limit' => 1..1000, 'max_steps' => 1..200 }
    ranges.each { |key, range| JrcNico::Helpdesk::Definition.bounded_integer!(value.fetch(key), range.min, range.max) }
    validate_effects!(value.fetch('allowed_effects'))
    true
  end

  def self.validate_effects!(effects)
    raise ArgumentError, 'Explicit supported flow effects required' unless effects.is_a?(Array) && effects.uniq == effects &&
                                                                           (effects - EFFECTS).empty?
  end

  def reason
    return 'playbook_flow_effects_disabled' unless @reference.effects_enabled?
    return 'playbook_flow_phase_not_approved' if definition.fetch('phase') > definition.fetch('approved_phase')
    return 'playbook_flow_company_not_in_pilot' unless company_allowed?
    return 'playbook_flow_actor_not_in_pilot' unless definition.fetch('pilot_account_user_ids').include?(@reference.context.member.id)
    return 'playbook_flow_unit_not_in_pilot' unless unit_allowed?
  end

  def unit_allowed?
    id = @reference.assignment.business_unit_id
    id ? definition.fetch('pilot_business_unit_ids').include?(id) : definition.fetch('allow_unassigned_business_unit')
  end

  def company_allowed?
    company_id = @reference.assignment.company_id || @reference.contact.company_id
    definition.fetch('pilot_company_ids').include?(company_id) &&
      JrcCustomers::Company.where(account_id: @reference.context.account.id).exists?(company_id)
  end

  def effect_allowed?(type)
    effect = MUTATIONS.fetch(type, type)
    phase_three = MUTATIONS.value?(effect) || DELIVERY_EFFECTS.include?(effect)
    return false if phase_three && (definition.fetch('phase') != 3 || definition.fetch('approved_phase') != 3)

    definition.fetch('allowed_effects').include?(effect)
  end

  def limit!(run: nil)
    scope = JrcFlowRun.where(account_id: @reference.context.account.id).where('created_at > ?', 1.hour.ago)
                      .where('event_key LIKE ?', 'relationship-playbook:%')
    scope = scope.where.not(id: run.id) if run
    raise ArgumentError, 'playbook_flow_hourly_limit' if scope.count >= definition.fetch('hourly_limit')
  end
end
