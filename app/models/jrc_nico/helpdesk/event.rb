class JrcNico::Helpdesk::Event < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_events'
  belongs_to :account
  belongs_to :policy_version, class_name: 'JrcNico::Helpdesk::PolicyVersion'
  belongs_to :ticket, class_name: 'JrcServiceDesk::Ticket'
  belongs_to :actor, class_name: 'AccountUser'
  has_many :approvals, class_name: 'JrcNico::Helpdesk::Approval', dependent: :restrict_with_error
  validates :rule_key, inclusion: { in: (1..16).map { |n| format('R%02d', n) } }
  validates :correlation_key, presence: true, length: { maximum: 255 }, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: %w[detected prepared succeeded blocked failed unknown cancelled] }
  validates :detected_at, presence: true
  validate :scope_integrity, :immutable_provenance

  private

  def scope_integrity
    errors.add(:account, 'scope mismatch') unless [policy_version&.account_id, ticket&.account_id, actor&.account_id].all?(account_id)
  end

  def immutable_provenance
    immutable = %w[account_id policy_version_id ticket_id actor_id rule_key correlation_key evidence detected_at]
    errors.add(:base, 'event provenance is immutable') if persisted? && changed.intersect?(immutable)
  end
end
