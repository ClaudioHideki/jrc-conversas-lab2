class JrcRelationship::Playbook < ApplicationRecord
  self.table_name = 'jrc_relationship_playbooks'
  belongs_to :account
  validates :name, :trigger_kind, presence: true
  validates :trigger_kind, inclusion: { in: %w[onboarded health satisfaction no_contact renewal ticket expansion cancellation] }
  validate do
    errors.add(:conditions, 'must be finite operational conditions') unless JrcRelationship::PlaybookConditions.valid?(conditions)
    Array(conditions).each do |condition|
      next unless condition.is_a?(Hash)
      target = { 'segment_id' => JrcCustomers::Taxonomy, 'product_id' => JrcCrm::Product, 'business_unit_id' => JrcCrm::BusinessUnit }[condition['field']]
      errors.add(:conditions, 'references must belong to this account') if target && !target.where(account_id: account_id, id: condition['value']).exists?
    end
    errors.add(:steps, 'must contain between 1 and 50 finite native workflow steps') unless JrcRelationship::PlaybookSteps.valid?(steps)
  end
end
