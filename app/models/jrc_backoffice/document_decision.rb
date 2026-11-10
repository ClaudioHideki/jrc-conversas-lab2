class JrcBackoffice::DocumentDecision < ApplicationRecord
  self.table_name = 'jrc_backoffice_document_decisions'
  belongs_to :document_version, class_name: 'JrcBackoffice::DocumentVersion'
  belongs_to :actor, class_name: 'User'
  validates :status, inclusion: { in: %w[approved rejected expired] }
  validates :reason, presence: true, length: { maximum: 2000 }
  validate :actor_belongs_to_account
  validate :valid_calendar_expiration
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Document decisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Document decisions are immutable' }

  private

  def valid_calendar_expiration
    if expires_on.nil?
      errors.add(:validity_timezone, 'must be absent without an expiration') if validity_timezone.present?
    elsif !Time.find_zone(validity_timezone)
      errors.add(:validity_timezone, 'must identify the calendar used for expiration')
    end
  end

  def actor_belongs_to_account
    return unless document_version && actor

    errors.add(:actor, 'must belong to account') unless document_version.account.users.exists?(actor.id)
  end
end
