class JrcRelationship::PlaybookVersion < ApplicationRecord
  self.table_name = 'jrc_relationship_playbook_versions'
  belongs_to :account
  belongs_to :playbook, class_name: 'JrcRelationship::Playbook'
  belongs_to :actor, class_name: 'User', optional: true
  validates :version, :payload, presence: true

  def readonly?
    persisted?
  end
end
