class JrcRelationship::HandoffCase < ApplicationRecord
  self.table_name = 'jrc_relationship_handoff_cases'
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  belongs_to :decided_by, class_name: 'User', optional: true
  validates :source_type, inclusion: { in: %w[JrcCrm::SalesOrder JrcProjects::Project] }
  validates :source_id, presence: true
  validates :status, inclusion: { in: %w[pending accepted rejected] }
  validate do
    errors.add(:assignment, 'wrong account') if assignment && assignment.account_id != account_id
    errors.add(:decided_by, 'wrong account') if decided_by && !account.users.exists?(decided_by_id)
    errors.add(:checklist, 'must be a bounded checklist') unless checklist.is_a?(Hash) && checklist.size <= 30 && checklist.values.all? do |v|
      [true, false].include?(v)
    end
    errors.add(:base, 'decision requires actor, date and reason') if (status != 'pending') && !(decided_by && decided_at && reason.present?)
    errors.add(:base, 'handoff decision is immutable') if persisted? && status_in_database != 'pending' && changed?
  end
end
