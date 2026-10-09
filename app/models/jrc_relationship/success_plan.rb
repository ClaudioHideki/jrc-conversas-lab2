class JrcRelationship::SuccessPlan < JrcRelationship::Record
  self.table_name = 'jrc_relationship_success_plans'
  belongs_to :project, class_name: 'JrcProjects::Project', optional: true
  belongs_to :contract, class_name: 'JrcCrm::Contract', optional: true
  belongs_to :product, class_name: 'JrcCrm::Product', optional: true
  validates :title, presence: true
  validates :status, inclusion: { in: %w[active completed paused canceled] }
  validate do
    errors.add(:goals, 'must be an array of metrics') unless goals.is_a?(Array) && goals.all? { |g| g.is_a?(Hash) && g['metric'].present? }
    Array(goals).each do |goal|
      next unless goal.is_a?(Hash)

      %w[baseline target current].each do |field|
        next if goal[field].blank?

        value = Float(goal[field], exception: false)
        errors.add(:goals, "#{field} must be a finite number") unless value&.finite?
      end
    end
    milestones = metadata['milestones'] || []
    unless milestones.is_a?(Array) && milestones.size <= 50 && milestones.all? { |row| row.is_a?(Hash) && row['title'].present? }
      errors.add(:metadata, 'milestones must be a bounded list with titles')
    end
  end
end
