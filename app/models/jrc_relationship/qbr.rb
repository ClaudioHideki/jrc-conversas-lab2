class JrcRelationship::Qbr < JrcRelationship::Record
  self.table_name = 'jrc_relationship_qbrs'
  belongs_to :activity, class_name: 'JrcCrm::Activity', optional: true
  validates :title, :scheduled_at, presence: true
  validates :status, inclusion: { in: %w[scheduled completed canceled] }
  validates :summary, presence: true, if: -> { status == 'completed' }
  validate do
    errors.add(:participants, 'must be a bounded list') unless participants.is_a?(Array) && participants.size <= 50 && participants.all? { |row| row.is_a?(Hash) }
    errors.add(:decisions, 'must be a bounded list') unless decisions.is_a?(Array) && decisions.size <= 50 && decisions.all? { |row| row.is_a?(Hash) }
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
end
