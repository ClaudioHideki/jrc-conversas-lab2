# A source-free progress receipt for an actor whose handoff changed ownership.
class JrcRelationship::ReviewedBatchReceiptView
  def initialize(review)
    @review = review
  end

  def call
    { 'id' => @review.id, 'state' => @review.state, 'revision' => @review.revision, 'digest' => @review.digest,
      'expires_at' => @review.expires_at.iso8601(6),
      'inputs' => @review.inputs.slice('ids', 'operation', 'owner_id', 'request_id', 'transfer_responsibilities'),
      'summary' => nil, 'distribution' => [], 'capacity' => [], 'responsibilities' => [], 'approval' => nil,
      'source_access_limited' => true, 'items' => @review.items.order(:ordinal).map do |item|
        { 'assignment_id' => item.assignment_id, 'label' => nil, 'state' => item.state,
          'receipt' => item.receipt, 'error_code' => item.error_code }
      end }
  end
end
