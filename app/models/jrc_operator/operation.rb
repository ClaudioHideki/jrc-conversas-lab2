class JrcOperator::Operation < ApplicationRecord
  self.table_name = 'jrc_operator_operations'
  belongs_to :binding, class_name: 'JrcOperator::Binding'
  belongs_to :user
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  belongs_to :prepared_operation, class_name: 'JrcOperator::Operation', optional: true
  has_one_attached :boleto
  validate :valid_scope
  validates :key, format: { with: /\A[a-zA-Z0-9_-]{16,128}\z/ }
  validates :kind, inclusion: { in: %w[reserve release prepare_boleto send_boleto] }
  validates :state, inclusion: { in: %w[pending confirmed rejected] }

  private

  def valid_scope
    valid_user_scope
    valid_conversation_scope
    valid_prepared_scope
  end

  def valid_user_scope
    errors.add(:user, 'must belong to account') unless binding && user && binding.account.account_users.exists?(user_id: user.id)
  end

  def valid_conversation_scope
    return unless conversation
    return if binding && conversation.account_id == binding.account_id && conversation.contact_id == binding.contact_id

    errors.add(:conversation, 'must match customer')
  end

  def valid_prepared_scope
    errors.add(:prepared_operation, 'must match binding') if prepared_operation && prepared_operation.binding_id != binding_id
  end
end
