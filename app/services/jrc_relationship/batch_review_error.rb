# Bounded operational diagnostics, never exception messages or validation values.
# Remains an ArgumentError for the existing native HTTP contract.
class JrcRelationship::BatchReviewError < ArgumentError
  TYPED_CODES = %w[BATCH_REVIEW_STALE BATCH_REVIEW_EXPIRED BATCH_RECEIPT_INVALID].freeze
  VALIDATION_CODES = {
    portfolio_capacity_exceeded: 'BATCH_CAPACITY_EXCEEDED',
    portfolio_capacity_unconfigured: 'BATCH_CAPACITY_UNCONFIGURED',
    portfolio_capacity_unavailable: 'BATCH_CAPACITY_UNAVAILABLE'
  }.freeze
  attr_reader :code

  def initialize(code, message)
    @code = code
    super(message)
  end

  def self.item_code(error)
    return error.code if error.is_a?(self) && TYPED_CODES.include?(error.code)
    return 'BATCH_REVIEW_STALE' if error.is_a?(ActiveRecord::StaleObjectError)
    return 'BATCH_NATIVE_OPERATION_FAILED' unless error.is_a?(ActiveRecord::RecordInvalid)

    error.record.errors.details.values.flatten.filter_map { |detail| VALIDATION_CODES[detail[:error]] }.first || 'BATCH_NATIVE_VALIDATION_FAILED'
  end
end
