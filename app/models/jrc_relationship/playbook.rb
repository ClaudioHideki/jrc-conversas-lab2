class JrcRelationship::Playbook < ApplicationRecord
  self.table_name = 'jrc_relationship_playbooks'
  belongs_to :account
  validates :name, :trigger_kind, presence: true
  validates :trigger_kind, inclusion: { in: %w[onboarded health satisfaction no_contact renewal ticket expansion cancellation] }
  validate do
    errors.add(:conditions, 'must be finite operational conditions') unless JrcRelationship::PlaybookConditions.valid?(conditions)
    errors.add(:steps, 'only activity and action steps are supported') unless steps.is_a?(Array) && steps.all? { |s| s.is_a?(Hash) && %w[activity action].include?(s['kind']) && s['title'].present? && s['after_days'].to_i.between?(0, 365) }
  end
end
