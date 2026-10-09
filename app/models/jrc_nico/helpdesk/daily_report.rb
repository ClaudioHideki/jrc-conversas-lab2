class JrcNico::Helpdesk::DailyReport < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_daily_reports'
  belongs_to :account
  belongs_to :policy_version, class_name: 'JrcNico::Helpdesk::PolicyVersion'
  belongs_to :recipient, class_name: 'AccountUser'
  validates :report_date, uniqueness: { scope: %i[account_id recipient_id scope_digest] }
  validates :scope_digest, :timezone, :cutoff_at, presence: true
  validate :scope_integrity

  private

  def scope_integrity
    errors.add(:account, 'scope mismatch') unless [policy_version&.account_id, recipient&.account_id].all?(account_id)
    errors.add(:base, 'report is immutable') if persisted? && changed?
  end
end
