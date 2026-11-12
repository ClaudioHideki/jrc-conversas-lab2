# Immutable facts added to the existing reviewed batch, never a second registry.
class JrcRelationship::DistributionPreview
  def initialize(context:, inputs:, records:, summary:)
    @context = context
    @inputs = inputs
    @records = records
    @summary = summary
  end

  def call
    validate_destination!
    @records.each { |row| JrcRelationship::PortfolioTransferLock.check!(row, owner_id: @inputs['owner_id']) }
    binding = JrcRelationship::DistributionApproval.new(@context).binding(@records, owner_id: @inputs['owner_id'])
    raise ArgumentError, 'A justification is required for formal distribution approval' if binding['required'] && @inputs['justification'].blank?

    minutes = @records.map { |row| @context.configuration(row).effective_rules.fetch('portfolio_review_validity_minutes') }.min
    minutes = JrcRelationship::PortfolioGroupConfiguration.review_validity(@context.account, binding, minutes)
    { 'distribution_approval' => binding, 'validity_minutes' => minutes, 'distribution' => comparison,
      'capacity' => JrcRelationship::DistributionCapacity.new(@context).preview(@inputs, @records) }
  end

  private

  def validate_destination!
    owner_id = @inputs['owner_id']
    return unless owner_id && @records.any? { |row| row.owner_id != owner_id }
    return if JrcRelationship::AnalystEligibility.available?(@context.account.id, owner_id)

    raise ArgumentError, 'Destination analyst is withdrawn from Relationship'
  end

  def comparison
    @records.map do |row|
      { 'assignment_id' => row.id, 'label' => row.label, 'from_owner_id' => row.owner_id, 'from_owner_name' => row.owner&.name,
        'to_owner_id' => @inputs['owner_id'], 'to_owner_name' => @summary['owner_name'] }
    end
  end
end
