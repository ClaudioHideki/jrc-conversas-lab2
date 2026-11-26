# frozen_string_literal: true

# A review DTO is not authority. The selected command must still authorize the
# current original agent, native destination and exact immutable source.
class JrcContactCenter::EndingActions::DestinationSelectionReview
  FIELDS = %w[confirmed expected_readiness_id expected_request_id expected_rule_sha256 expected_version_id].freeze

  def initialize(review, request_id: true)
    @review = review
    @with_request_id = request_id
    @fields = request_id ? FIELDS : FIELDS - ['expected_request_id']
  end

  def validate!
    valid = valid_document?
    valid &&= @review.values_at('expected_readiness_id', 'expected_version_id').all? { |value| identifier?(value) }
    valid &&= request_id_valid?
    valid &&= digest?(@review['expected_rule_sha256'])
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid
  end

  def verify!(attempt)
    validate!
    actual = [attempt.readiness_id.to_s, attempt.request_key, attempt.rule_sha256, attempt.version_id.to_s]
    expected = @review.values_at('expected_readiness_id', 'expected_request_id', 'expected_rule_sha256', 'expected_version_id')
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless actual == expected
  end

  private

  def valid_document?
    @review.is_a?(Hash) && @review.keys.sort == @fields && @review['confirmed'] == true
  end

  def identifier?(value)
    value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
  end

  def request_id_valid?
    return true unless @with_request_id

    value = @review['expected_request_id']
    value.is_a?(String) && value.match?(/\A[0-9a-f-]{36}\z/)
  end

  def digest?(value)
    value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
  end
end
