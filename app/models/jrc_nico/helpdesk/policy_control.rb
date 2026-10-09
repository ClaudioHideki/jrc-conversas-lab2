class JrcNico::Helpdesk::PolicyControl < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_policy_controls'
  belongs_to :account
  belongs_to :policy_version, class_name: 'JrcNico::Helpdesk::PolicyVersion'
  validates :policy_version_id, uniqueness: { scope: :account_id }
  validates :halted, inclusion: { in: [true, false] }
  validate :control_integrity, :immutable_ownership

  private

  def control_integrity
    errors.add(:policy_version, 'outside Account') unless policy_version&.account_id == account_id
    errors.add(:halted_at, 'requires a halt') unless halted? == !halted_at.nil?
    errors.add(:halted, 'cannot reactivate through the disable control') if halted_in_database && !halted?
  end

  def immutable_ownership
    errors.add(:base, 'control ownership is immutable') if persisted? && changed.intersect?(%w[account_id policy_version_id])
  end
end
