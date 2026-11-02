class JrcBackoffice::DocumentDecision < ApplicationRecord
  self.table_name = 'jrc_backoffice_document_decisions'
  belongs_to :document_version, class_name: 'JrcBackoffice::DocumentVersion'
  belongs_to :actor, class_name: 'User'
  validates :status, inclusion: { in: %w[approved rejected expired] }
  validates :reason, presence: true, length: { maximum: 2000 }
  validate :actor_belongs_to_account
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Document decisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Document decisions are immutable' }

  private

  def actor_belongs_to_account
    return unless document_version && actor

    errors.add(:actor, 'must belong to account') unless document_version.account.users.exists?(actor.id)
  end
end
