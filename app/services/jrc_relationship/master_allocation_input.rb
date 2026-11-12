class JrcRelationship::MasterAllocationInput
  FIELDS = (JrcRelationship::AssignmentCreation::FIELDS - ['contact_id'] + ['exception_reason']).freeze
  SCOPE_IDS = %w[owner_id team_id business_unit_id].freeze

  def initialize(context)
    @context = context
  end

  def call(input)
    raise Pundit::NotAuthorizedError unless @context.policy.team?

    allowed = %w[operation ids request_id portfolio_group_id expected_version justification creations previous_review_id]
    raise ArgumentError, 'Unsupported master allocation review fields' unless (input.keys - allowed).empty?

    fields = JrcRelationship::PortfolioMembershipInput.new(@context).call(input.except('previous_review_id').merge('active' => true))
    result = fields.except('active').merge('creations' => creations(input, fields.fetch('ids')))
    result['previous_review_id'] = previous_review!(input, result) if input.key?('previous_review_id')
    result
  end

  private

  def creations(input, ids)
    entries = input.fetch('creations', [])
    valid = entries.is_a?(Array) && entries.size <= 50 && entries.to_json.bytesize <= 128.kilobytes
    raise ArgumentError, 'Use a bounded native allocation proposal' unless valid

    rows = entries.map { |row| normalize_creation(row, ids) }
    raise ArgumentError, 'Duplicate native allocation proposal' unless rows.pluck('company_id').uniq.size == rows.size

    rows.sort_by { |row| row.fetch('company_id') }
  end

  def normalize_creation(row, ids)
    raise ArgumentError, 'Unsupported native allocation proposal fields' unless row.is_a?(Hash) && (row.keys - FIELDS).empty?

    value = row.deep_dup
    value['company_id'] = JrcRelationship::PortfolioOwnerInput.parse(value.fetch('company_id'))
    raise ArgumentError, 'Allocation proposal must belong to the selected master audience' unless ids.include?(value['company_id'])

    SCOPE_IDS.each { |key| value[key] = JrcRelationship::PortfolioOwnerInput.parse(value[key]) if value.key?(key) }
    validate_settings!(value)
    value
  end

  def validate_settings!(row)
    if row.key?('settings')
      settings = row['settings']
      valid = settings.is_a?(Hash) && (settings.keys - JrcRelationship::AssignmentCreation::SETTINGS).empty?
      raise ArgumentError, 'Unsupported native allocation settings' unless valid
    end
    return unless row.key?('exception_reason')

    reason = row['exception_reason']
    raise ArgumentError, 'Provide an explicit bounded eligibility exception' unless reason.is_a?(String) && reason.strip.length.between?(1, 2000)

    row['exception_reason'] = reason.strip
  end

  def previous_review!(input, result)
    id = JrcRelationship::PortfolioOwnerInput.parse(input.fetch('previous_review_id'))
    prior = JrcRelationship::BatchReview.where(account_id: @context.account.id, actor_id: @context.user.id).find(id)
    valid = prior.state.in?(%w[attention canceled]) && prior.inputs['operation'] == 'master_allocation' &&
            prior.inputs['portfolio_group_id'] == result.fetch('portfolio_group_id')
    unresolved = prior.items.where(state: %w[failed canceled]).pluck(:company_id)
    raise ArgumentError, 'Choose only unresolved master subjects from the prior review' unless valid && (result.fetch('ids') - unresolved).empty?

    prior.id
  end
end
