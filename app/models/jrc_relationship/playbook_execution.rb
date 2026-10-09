class JrcRelationship::PlaybookExecution < ApplicationRecord
  self.table_name = 'jrc_relationship_playbook_executions'
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  belongs_to :playbook, class_name: 'JrcRelationship::Playbook'
  belongs_to :actor, class_name: 'User'
  # Executions project the finite steps into existing native records; planned is not provider delivery or activity completion.
  validates :status, inclusion: { in: %w[planned] }
  validates :execution_key, :source_key, :snapshot, :version, presence: true
  validate do
    errors.add(:base, 'execution references must belong to account') unless assignment&.account_id == account_id &&
                                                                            playbook&.account_id == account_id && account.users.exists?(actor_id)
  end

  def readonly?
    persisted?
  end
end
