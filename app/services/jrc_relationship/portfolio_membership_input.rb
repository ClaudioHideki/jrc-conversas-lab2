# A new operation in the existing reviewed engine, not an ownership transfer.
class JrcRelationship::PortfolioMembershipInput
  def initialize(context)
    @context = context
  end

  def call(input)
    ids = JrcRelationship::PortfolioGroupCustomerInput.parse(input.fetch('ids'))
    result = membership_fields(input).merge('ids' => ids)
    result['previous_review_id'] = previous_review!(input, result) if input.key?('previous_review_id')
    result
  end

  private

  def membership_fields(input)
    group_id = JrcRelationship::PortfolioOwnerInput.parse(input.fetch('portfolio_group_id'))
    revision = input.fetch('expected_version')
    reason = input.fetch('justification')
    raise ArgumentError, 'A portfolio and whole-number revision are required' unless group_id && revision.is_a?(Integer) && revision >= 0
    raise ArgumentError, 'Use an explicit membership boolean' unless [true, false].include?(input.fetch('active'))
    raise ArgumentError, 'Provide a bounded membership reason' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)

    { 'portfolio_group_id' => group_id, 'expected_version' => revision,
      'active' => input.fetch('active'), 'justification' => reason.strip }
  end

  def previous_review!(input, result)
    id = JrcRelationship::PortfolioOwnerInput.parse(input.fetch('previous_review_id'))
    prior = JrcRelationship::BatchReview.where(account_id: @context.account.id, actor_id: @context.user.id).find(id)
    expected = result.slice('portfolio_group_id', 'active').merge('operation' => 'portfolio_membership')
    valid = prior.state.in?(%w[attention canceled]) && prior.inputs.slice(*expected.keys) == expected
    unresolved = prior.items.where(state: %w[failed canceled]).pluck(:assignment_id)
    raise ArgumentError, 'Choose only unresolved items from the prior terminal review' unless valid && (result.fetch('ids') - unresolved).empty?

    prior.id
  end
end
