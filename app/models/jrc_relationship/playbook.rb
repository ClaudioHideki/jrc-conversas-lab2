class JrcRelationship::Playbook < ApplicationRecord
  self.table_name = 'jrc_relationship_playbooks'
  belongs_to :account
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  has_many :versions, class_name: 'JrcRelationship::PlaybookVersion', dependent: :restrict_with_error

  def snapshot
    attributes.slice('id', 'name', 'trigger_kind', 'active', 'version', 'steps', 'conditions')
  end
  validates :name, :trigger_kind, presence: true
  validates :trigger_kind, inclusion: { in: %w[onboarded health satisfaction no_contact renewal ticket expansion cancellation] }
  validate do
    errors.add(:conditions, 'must be finite operational conditions') unless JrcRelationship::PlaybookConditions.valid?(conditions)
    Array(conditions).each do |condition|
      next unless condition.is_a?(Hash)

      target = { 'segment_id' => JrcCustomers::Taxonomy, 'product_id' => JrcCrm::Product,
                 'business_unit_id' => JrcCrm::BusinessUnit }[condition['field']]
      errors.add(:conditions, 'references must belong to this account') if target && !target.exists?(account_id: account_id, id: condition['value'])
    end
    errors.add(:steps, 'must contain between 1 and 50 finite native workflow steps') unless JrcRelationship::PlaybookSteps.valid?(steps)
    next unless new_record? || will_save_change_to_steps?

    Array(steps).select { |step| step.is_a?(Hash) && step['kind'] == 'flow' }.each do |step|
      references = { 'flow_id' => JrcFlow, 'conversation_id' => Conversation, 'contact_id' => Contact, 'business_unit_id' => JrcCrm::BusinessUnit }
      references.each do |key, model|
        next if key == 'business_unit_id' && step[key].nil?

        errors.add(:steps, 'flow references must belong to account') unless model.exists?(account_id: account_id, id: step[key])
      end
      next unless step.key?('message_id')

      begin
        conversation = Conversation.where(account_id: account_id).find(step['conversation_id'])
        JrcRelationship::PlaybookFlowInput.find!(account: account, conversation: conversation,
                                                contact_id: step['contact_id'], message_id: step['message_id'])
      rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
        errors.add(:steps, 'flow message must be the explicitly selected native incoming contact message')
      end
    end
  end
end
