class JrcNico::Helpdesk::ControlEvent < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_control_events'
  belongs_to :account
  belongs_to :policy_version, class_name: 'JrcNico::Helpdesk::PolicyVersion'
  belongs_to :actor, class_name: 'AccountUser'
  validates :action, inclusion: { in: ['disable'] }
  validates :request_key, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id policy_version_id actor_id] }
  validates :reason, presence: true, length: { maximum: 1000 }
  validates :occurred_at, presence: true
  validate :scope_integrity

  def readonly?
    persisted?
  end

  private

  def scope_integrity
    errors.add(:base, 'outside Account') unless [policy_version&.account_id, actor&.account_id].all?(account_id)
  end
end
