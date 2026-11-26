# frozen_string_literal: true

# A review DTO is not authority. The selected command must still authorize the
# current original agent, native destination and exact immutable source.
class JrcContactCenter::EndingActions::DestinationSelectionReview
  FIELDS = %w[confirmed expected_readiness_id expected_request_id expected_rule_sha256 expected_version_id].freeze

  def initialize(review)
    @review = review
  end

  def validate!
    valid = @review.is_a?(Hash) && @review.keys.sort == FIELDS && @review['confirmed'] == true
    valid &&= @review.values_at('expected_readiness_id', 'expected_version_id').all? do |value|
      value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
    end
    valid &&= @review['expected_request_id'].is_a?(String) && @review['expected_request_id'].match?(/\A[0-9a-f-]{36}\z/)
    valid &&= @review['expected_rule_sha256'].is_a?(String) && @review['expected_rule_sha256'].match?(/\A[a-f0-9]{64}\z/)
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid
  end

  def verify!(attempt)
    validate!
    actual = [attempt.readiness_id.to_s, attempt.request_key, attempt.rule_sha256, attempt.version_id.to_s]
    expected = @review.values_at('expected_readiness_id', 'expected_request_id', 'expected_rule_sha256', 'expected_version_id')
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless actual == expected
  end
end
