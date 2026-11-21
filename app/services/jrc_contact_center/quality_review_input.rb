# frozen_string_literal: true

# Internal human-review value only. This is neither authorization nor a provider/recording mutation.
class JrcContactCenter::QualityReviewInput
  CLASSIFICATIONS = %w[positive neutral negative].freeze
  FIELDS = %w[classification adjusted_summary adjusted_themes recommendation_ids justification
              expected_revision expected_source_sha256 request_id].freeze
  SHA256 = /\A[0-9a-f]{64}\z/
  UUID = /\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i
  attr_reader :attributes

  def initialize(values)
    valid = values.is_a?(Hash) && values.keys.all?(String) && (values.keys - FIELDS).empty?
    invalid! unless valid
    reason!(values['justification'])
    classification!(values['classification'])
    content!(values)
    precondition!(values)
    @attributes = normalized(values)
    deep_freeze(@attributes)
  end

  # The caller must obtain these from the freshly authorized source, never from request parameters.
  def validate_source!(actual_sha256:, available_recommendation_ids:)
    valid = digest?(actual_sha256)
    valid &&= available_recommendation_ids.is_a?(Array) && available_recommendation_ids.all? { |value| digest?(value) }
    invalid! unless valid
    expected = attributes.fetch('expected_source_sha256')
    unless ActiveSupport::SecurityUtils.secure_compare(expected, actual_sha256)
      raise JrcContactCenter::OperationError.new('quality_review_source_changed', status: :conflict)
    end

    invalid! unless (attributes.fetch('recommendation_ids') - available_recommendation_ids).empty?

    self
  end

  private

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_quality_review'
  end

  def reason!(value)
    return if value.is_a?(String) && value.valid_encoding? && value.strip.present?

    raise JrcContactCenter::OperationError, 'quality_review_justification_required'
  end

  def classification!(value)
    return if CLASSIFICATIONS.include?(value)

    raise JrcContactCenter::OperationError, 'quality_review_classification_required'
  end

  def text?(value, maximum:, empty: false)
    value.is_a?(String) && value.valid_encoding? && value.bytesize <= maximum &&
      (empty || value.strip.present?) && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
  end

  def content!(values)
    valid = text?(values['justification'], maximum: 8_000) && text?(values['adjusted_summary'], maximum: 48_000, empty: true)
    valid &&= themes?(values['adjusted_themes']) && recommendations?(values['recommendation_ids'])
    invalid! unless valid
  end

  def themes?(values)
    values.is_a?(Array) && values.length <= 40 && values.all? { |value| text?(value, maximum: 640) }
  end

  def digest?(value)
    value.is_a?(String) && value.valid_encoding? && value.match?(SHA256)
  end

  def recommendations?(values)
    values.is_a?(Array) && values.length <= 40 && values.all? { |value| digest?(value) }
  end

  def precondition!(values)
    revision = values['expected_revision']
    valid = revision.is_a?(Integer) && revision.between?(0, 2_147_483_647)
    valid &&= digest?(values['expected_source_sha256'])
    request_id = values['request_id']
    valid &&= request_id.is_a?(String) && request_id.valid_encoding? && request_id.match?(UUID)
    invalid! unless valid
  end

  def normalized(values)
    result = values.deep_dup
    result['justification'] = result.fetch('justification').strip
    result['adjusted_themes'] = result.fetch('adjusted_themes').map(&:strip).uniq
    result['recommendation_ids'] = result.fetch('recommendation_ids').uniq.sort
    result['request_id'] = result.fetch('request_id').downcase
    result
  end

  def deep_freeze(value)
    case value
    when Hash
      value.each do |key, child|
        key.freeze
        deep_freeze(child)
      end
    when Array
      value.each { |child| deep_freeze(child) }
    end
    value.freeze
  end
end
