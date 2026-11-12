class JrcRelationship::MasterAllocationProjection
  def initialize(context)
    @context = context
  end

  def call(review)
    JrcRelationship::MasterAllocationReview.new(@context).authorize_read!(review)
    JrcRelationship::BatchReviewIdentity.call(review).merge(
      'summary' => review.snapshot.fetch('summary'),
      'master_capacity' => JrcRelationship::MasterAllocationCapacity.new(@context).for_view(review.snapshot.fetch('master_capacity')),
      'items' => review.items.order(:ordinal).map { |item| present_item(review, item) }
    )
  end

  private

  def present_item(review, item)
    row = review.snapshot.fetch('rows').fetch(item.ordinal)
    { 'assignment_id' => item.assignment_id, 'company_id' => item.company_id, 'label' => row.fetch('label'),
      'state' => item.state, 'receipt' => item.receipt, 'error_code' => item.error_code,
      'mode' => row.fetch('mode'), 'allocation' => row.fetch('allocation') }
  end
end
