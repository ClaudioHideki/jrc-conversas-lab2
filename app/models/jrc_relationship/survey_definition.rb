class JrcRelationship::SurveyDefinition < ApplicationRecord
  self.table_name = 'jrc_relationship_survey_definitions'
  belongs_to :account
  validates :name, presence: true, length: { maximum: 120 }
  validates :code, format: { with: /\A[a-z0-9_-]{1,60}\z/ }, uniqueness: { scope: :account_id }
  validates :kind, inclusion: { in: %w[nps csat ces custom] }
  validates :status, inclusion: { in: %w[draft active archived] }
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validate :valid_questions
  validate :valid_settings

  def snapshot
    attributes.slice('id', 'name', 'code', 'kind', 'version', 'questions', 'settings')
  end

  def available_at?(time)
    self.class.available_at?(settings, time)
  end

  def self.available_at?(settings, time)
    lower = settings['available_from'].presence && Time.iso8601(settings['available_from'])
    upper = settings['available_until'].presence && Time.iso8601(settings['available_until'])
    (!lower || time >= lower) && (!upper || time <= upper)
  end

  private

  def valid_questions
    schema = JrcRelationship::SurveyQuestionSchema.new(questions)
    unless schema.valid?
      errors.add(:questions, 'must contain unique bounded questions and valid backward conditions')
      return
    end
    errors.add(:questions, 'the principal question must require the declared scale') unless schema.principal_scale?(kind)
  end

  def valid_settings
    errors.add(:settings, 'must be a bounded object') unless settings.is_a?(Hash) && (settings.keys - %w[low_threshold recovery_enabled
                                                                                                         recovery_sla_hours thank_you ces_direction
                                                                                                         available_from available_until]).empty?
    return unless settings.is_a?(Hash)

    if settings.key?('recovery_enabled') && [true, false].exclude?(settings['recovery_enabled'])
      errors.add(:settings, 'recovery_enabled must be boolean')
    end
    validate_numeric_setting('low_threshold', 0..100)
    validate_numeric_setting('recovery_sla_hours', 1..8760)
    validate_thank_you
    validate_direction
    validate_validity
  end

  def validate_thank_you
    text = settings['thank_you']
    errors.add(:settings, 'thank you must be bounded text') if text && (!text.is_a?(String) || text.length > 1000)
  end

  def validate_numeric_setting(key, range)
    value = settings[key]
    return unless value
    return if value.is_a?(Numeric) && value.finite? && range.cover?(value)

    errors.add(:settings, "invalid #{key}")
  end

  def validate_direction
    direction = settings['ces_direction']
    return if direction.nil?
    return if kind == 'ces' && %w[higher_is_better lower_is_better].include?(direction)

    errors.add(:settings, 'CES direction must match the declared survey kind')
  end

  def validate_validity
    values = %w[available_from available_until].map do |key|
      next if settings[key].blank?

      value = settings[key]
      raise ArgumentError unless value.is_a?(String) && value.length <= 40 && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)

      Time.iso8601(value)
    end
    errors.add(:settings, 'invalid survey availability period') if values.all? && values.first > values.last
  rescue ArgumentError
    errors.add(:settings, 'availability must be an explicit ISO8601 timestamp with timezone')
  end
end
