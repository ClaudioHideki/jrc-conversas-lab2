class JrcNico::Helpdesk::DeliveryReceipt < ApplicationRecord
  self.table_name = 'jrc_nico_helpdesk_delivery_receipts'
  belongs_to :account
  belongs_to :recipient, class_name: 'AccountUser'
  validates :source_type, inclusion: { in: %w[event daily_report] }
  validates :channel, inclusion: { in: %w[nico email whatsapp] }, uniqueness: { scope: %i[account_id recipient_id source_type source_id] }
  validates :state, inclusion: { in: %w[pending dispatching sent delivered failed blocked unknown] }
  validates :attempt_number, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :scope_integrity

  def source
    model = source_type == 'event' ? JrcNico::Helpdesk::Event : JrcNico::Helpdesk::DailyReport
    model.where(account_id: account_id).find(source_id)
  end

  private

  def scope_integrity
    errors.add(:recipient, 'outside account') unless recipient&.account_id == account_id
    errors.add(:delivered_at, 'requires confirmed delivery') unless (state == 'delivered') == !delivered_at.nil?
    errors.add(:base, 'confirmed receipts are immutable') if state_in_database == 'delivered' && changed?
    if persisted? && changes.keys.intersect?(%w[account_id recipient_id source_type source_id channel])
      errors.add(:base, 'receipt identity is immutable')
    end
    if %w[sent unknown].include?(state_in_database) && changed?
      errors.add(:base, 'accepted or uncertain receipts require reconciliation')
    end
  end
end
