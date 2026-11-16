class JrcBroker::HistoryRetention
  class Protected < StandardError
    def initialize
      super('Este registro possui histórico preservado pelo Broker. Remova a conexão sem excluir o histórico.')
    end
  end

  def self.check!(record)
    raise Protected if new(record).retained?
  end

  def self.guard(record, &operation)
    new(record).guard(&operation)
  end

  def initialize(record)
    @record = record
  end

  def guard
    return yield unless supported?

    ApplicationRecord.transaction do
      # LIVE and V2 hold FOR SHARE on this same Account before resolving their
      # destination. Take the exclusive lock before any dependent cleanup, and
      # keep it until deletion commits. A queued job is never its own authority.
      Account.lock.find_by(id: account_id) if account_id
      ActiveStorage::Blob.lock.find_by(id: @record.id) if @record.is_a?(ActiveStorage::Blob)
      ActiveStorage::Blob.lock.find_by(id: @record.blob_id) if @record.is_a?(ActiveStorage::Attachment)
      self.class.check!(@record)
      yield
    end
  end

  def retained?
    case @record
    when Account then custody?(account_id: @record.id)
    when Inbox then custody?(account_id: @record.account_id, inbox_id: @record.id)
    when Conversation then conversation_custody?(@record.account_id, Conversation.where(id: @record.id))
    when Contact then conversation_custody?(@record.account_id, @record.conversations)
    when ContactInbox then conversation_custody?(account_id, @record.conversations)
    when Message then message_custody?(@record.account_id, [@record.id])
    when Attachment then self.class.new(@record.message).retained? || blob_custody?(@record.file_attachment&.blob_id)
    when ActiveStorage::Attachment then storage_attachment_custody?
    when ActiveStorage::Blob then blob_custody?(@record.id)
    when JrcBrokerLiveReceipt, JrcBrokerHistoryReceipt, JrcBrokerHistoryMedia then @record.persisted?
    else false
    end
  end

  private

  def supported?
    [Account, Inbox, Conversation, Contact, ContactInbox, Message, Attachment,
     JrcBrokerLiveReceipt, JrcBrokerHistoryReceipt, JrcBrokerHistoryMedia,
     ActiveStorage::Blob, ActiveStorage::Attachment].any? { |model| @record.is_a?(model) }
  end

  def account_id
    case @record
    when Account then @record.id
    when ContactInbox then @record.inbox&.account_id || @record.contact&.account_id
    when ActiveStorage::Attachment then @record.record.account_id if @record.record.is_a?(Attachment)
    else @record.account_id if @record.respond_to?(:account_id)
    end
  end

  def custody?(conditions)
    JrcBrokerLiveReceipt.exists?(conditions) || JrcBrokerHistoryReceipt.exists?(conditions) || JrcBrokerHistoryMedia.exists?(conditions)
  end

  def conversation_custody?(tenant_id, conversations)
    JrcBrokerLiveReceipt.where(account_id: tenant_id, conversation_id: conversations.select(:display_id)).exists? ||
      JrcBrokerHistoryReceipt.where(account_id: tenant_id, conversation_id: conversations.select(:id)).exists? ||
      JrcBrokerHistoryMedia.where(account_id: tenant_id, message_id: Message.where(conversation_id: conversations.select(:id)).select(:id)).exists?
  end

  def message_custody?(tenant_id, ids)
    custody?(account_id: tenant_id, message_id: ids)
  end

  def blob_custody?(blob_id)
    return false unless blob_id
    return true if JrcBrokerLiveReceipt.exists?(blob_id: blob_id) || JrcBrokerHistoryMedia.exists?(blob_id: blob_id)

    attachment_ids = ActiveStorage::Attachment.where(blob_id: blob_id, record_type: 'Attachment').select(:record_id)
    message_ids = Attachment.where(id: attachment_ids).select(:message_id)
    JrcBrokerLiveReceipt.where(message_id: message_ids).exists? || JrcBrokerHistoryReceipt.where(message_id: message_ids).exists?
  end

  def storage_attachment_custody?
    (@record.record.is_a?(Attachment) && self.class.new(@record.record).retained?) || blob_custody?(@record.blob_id)
  end
end
