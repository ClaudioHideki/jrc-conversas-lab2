class JrcRelationship::Qbr < JrcRelationship::Record
  self.table_name = 'jrc_relationship_qbrs'
  belongs_to :activity, class_name: 'JrcCrm::Activity', optional: true
  belongs_to :contact, optional: true
  belongs_to :contract, class_name: 'JrcCrm::Contract', optional: true
  belongs_to :product, class_name: 'JrcCrm::Product', optional: true
  validates :title, :scheduled_at, presence: true
  validates :status, inclusion: { in: %w[scheduled completed canceled] }
  validates :summary, presence: true, if: -> { status == 'completed' }
  validates :provider, inclusion: { in: %w[external] }
  after_save :remember_completed_survey
  after_commit :queue_completed_survey, on: %i[create update]
  after_rollback { @completed_survey_cycle_key = nil }
  validate do
    %w[meeting_url recording_url].each do |key|
      value = public_send(key)
      next if value.blank?

      uri = URI.parse(value)
      errors.add(key, 'must be an authorized HTTPS URL') unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
    rescue URI::InvalidURIError
      errors.add(key, 'invalid URL')
    end
  end
  validate do
    errors.add(:participants, 'must be a bounded list') unless participants.is_a?(Array) && participants.size <= 50 && participants.all?(Hash)
    errors.add(:decisions, 'must be a bounded list') unless decisions.is_a?(Array) && decisions.size <= 50 && decisions.all?(Hash)
    keys = Array(decisions).each_with_index.map { |row, index| row.is_a?(Hash) ? row.fetch('decision_key', index.to_s).to_s : index.to_s }
    unless keys.uniq.size == keys.size && keys.all? { |key| key.match?(/\A[a-zA-Z0-9_-]{1,64}\z/) }
      errors.add(:decisions, 'commitments require unique bounded identifiers')
    end
    Array(participants).each do |row|
      next unless row.is_a?(Hash) && row['participant_type']

      errors.add(:participants, 'invalid participant type') unless %w[internal external].include?(row['participant_type'])
      errors.add(:participants, 'internal participants require an existing user') if row['participant_type'] == 'internal' && row['user_id'].blank?
    end
    if status == 'completed' && Array(decisions).any? { |row| row.is_a?(Hash) && row['title'].present? && row['due_at'].blank? }
      errors.add(:decisions, 'commitments require a deadline for the native Agenda')
    end
  end

  private

  def remember_completed_survey
    return unless saved_change_to_status? && status == 'completed'

    @completed_survey_cycle_key = "qbr:#{id}:#{scheduled_at.utc.iso8601(6)}"
  end

  def queue_completed_survey
    cycle = @completed_survey_cycle_key
    @completed_survey_cycle_key = nil
    JrcRelationship::SurveyClosureJob.perform_later(self.class.name, id, cycle) if cycle
  end
end
