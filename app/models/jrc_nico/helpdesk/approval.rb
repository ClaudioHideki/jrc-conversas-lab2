class JrcNico::Helpdesk::Approval < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_approvals'
  belongs_to :account
  belongs_to :event, class_name: 'JrcNico::Helpdesk::Event'
  belongs_to :command, class_name: 'JrcNico::Command'
  belongs_to :approver, class_name: 'AccountUser'
  validates :command_id, uniqueness: true
  validates :state, inclusion: { in: %w[pending approved executing succeeded failed unknown cancelled reconciled] }
  validates :payload_digest, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :expires_at, presence: true
  validate :scope_integrity, :command_ownership, :immutable_payload

  private

  def scope_integrity
    errors.add(:account, 'scope mismatch') unless [event&.account_id, command&.session&.account_id, approver&.account_id].all?(account_id)
  end

  def command_ownership
    errors.add(:approver, 'must own native command') unless command&.session&.user_id == approver&.user_id
  end

  def immutable_payload
    immutable = %w[account_id event_id command_id approver_id payload_digest scope expires_at]
    errors.add(:base, 'approval payload is immutable') if persisted? && changed.intersect?(immutable)
  end
end
