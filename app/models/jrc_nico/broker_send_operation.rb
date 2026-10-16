class JrcNico::BrokerSendOperation < ApplicationRecord
  self.table_name = 'jrc_nico_broker_send_operations'
  STATES = %w[PREVIEW PAUSING DRAINING UNKNOWN MESSAGE_CREATED COMPLETED CANCELING CANCELED HALTED].freeze
  ACTIVE_STATES = %w[PAUSING DRAINING UNKNOWN MESSAGE_CREATED CANCELING].freeze

  belongs_to :command, class_name: 'JrcNico::Command', optional: true
  belongs_to :account
  belongs_to :user, optional: true
  belongs_to :conversation
  belongs_to :inbox
  belongs_to :message, optional: true
  attr_readonly :account_id, :user_id, :actor_id, :conversation_id, :inbox_id, :integration_id, :request_id,
                :snapshot, :recipient_snapshot, :fingerprint
  before_validation :capture_actor, on: :create
  validates :command, :user, presence: true, on: :create
  validates :actor_id, numericality: { only_integer: true, greater_than: 0 }
  validates :state, inclusion: { in: STATES }
  validates :fingerprint, format: { with: /\A[a-f0-9]{64}\z/ }
  validates :request_id, uniqueness: { scope: :account_id }
  validate :same_account_and_operator, on: :create
  validate :message_in_scope
  validate :immutable_creation_fact
  validate :immutable_command_reference
  after_commit :enqueue_confirmed, on: :update

  def receipt
    { phase: state, operation_id: id, conversation_id: conversation.display_id, contact: conversation.contact.name,
      takeover_id: takeover_id, message_id: message_id, delivery: message&.status,
      message_created_at: message_created_at, error: last_error,
      cancelable: message_created_at.nil? && message_id.nil? && %w[PREVIEW PAUSING DRAINING UNKNOWN].include?(state) }.compact
  end

  def claim
    with_operation_lock do
      next unless ACTIVE_STATES.include?(state)
      next if next_attempt_at && next_attempt_at > Time.current
      next if lease_expires_at && lease_expires_at > Time.current

      token = SecureRandom.uuid
      update!(lease_token: token, lease_expires_at: 90.seconds.from_now, attempts: attempts + 1)
      token
    end
  end

  def with_claim(token)
    with_operation_lock do
      next unless lease_token == token && lease_expires_at && lease_expires_at > Time.current

      yield
    end
  end

  def update_command!(attributes)
    command&.update!(attributes)
  end

  def canonical_message?
    ActiveRecord::Base.uncached do
      current_message = Message.find_by(id: message_id)
      next false unless current_message && User.exists?(id: user_id)

      [current_message.account_id == account_id, current_message.conversation_id == conversation_id,
       current_message.sender_type == 'User', current_message.sender_id == actor_id,
       current_message.outgoing?, !current_message.private?].all?
    end
  end

  def orphaned_intent?
    !message_created_at && (!command || !user)
  end

  def reconciliation_state
    return 'MESSAGE_CREATED' if message_created_at

    takeover_id ? 'DRAINING' : 'UNKNOWN'
  end

  private

  def with_operation_lock(&)
    current_command = command
    return with_lock(&) unless current_command

    current_command.with_lock { with_lock(&) }
  end

  def capture_actor
    self.actor_id = user_id
  end

  def immutable_command_reference
    return unless persisted? && will_save_change_to_command_id? && command_id

    errors.add(:command, 'O comando original não pode ser substituído.')
  end

  def immutable_creation_fact
    return unless persisted? && message_created_at_in_database

    errors.add(:message_created_at, 'O fato de criação da mensagem é permanente.') if will_save_change_to_message_created_at?
    errors.add(:message, 'O recibo original não pode ser substituído.') if will_save_change_to_message_id? && message_id
  end

  def enqueue_confirmed
    transition = previous_changes['state']
    JrcNico::BrokerSendJob.perform_later(id) if transition == %w[PREVIEW PAUSING] || transition&.last == 'CANCELING'
  end

  def same_account_and_operator
    return unless [command, conversation, inbox].all?

    valid = [command.session.account_id, conversation.account_id, inbox.account_id].all?(account_id) &&
            command.session.user_id == user_id && conversation.inbox_id == inbox_id
    errors.add(:base, 'Operação fora do escopo da conta, conversa ou operador.') unless valid
  end

  def message_in_scope
    return unless message && (new_record? || will_save_change_to_message_id?)

    valid = [message.account_id == account_id, message.conversation_id == conversation_id,
             message.sender_type == 'User', message.sender_id == actor_id, message.outgoing?, !message.private?].all?
    errors.add(:message, 'Recibo fora do escopo da operação.') unless valid
  end
end
