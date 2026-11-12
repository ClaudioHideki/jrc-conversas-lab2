class JrcBroker::HistorySyncMediaJob < ApplicationJob
  queue_as :low

  def perform(id)
    intent = JrcBrokerHistoryMedia.find_by(id: id)
    return unless intent&.state == 'ATTACH_PENDING' && ENV['JRC_HISTORY_SYNC_V2_ENABLED'] == 'true'

    importer = intent.importer
    importer.with_scope(intent.inbox_id, intent.scope_input) { |_scope| nil }
    JrcBroker::HistorySyncMedia.new(importer).verify_blob!(intent.blob, intent.descriptor)
    persist_attachment!(importer, intent)
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, ArgumentError, ActiveStorage::FileNotFoundError,
         ActiveStorage::IntegrityError, IOError, SystemCallError, Timeout::Error
    retry_intent!(id)
  end

  private

  def persist_attachment!(importer, intent)
    importer.with_scope(intent.inbox_id, intent.scope_input) do |scope|
      current = JrcBrokerHistoryMedia.lock.find(intent.id)
      next unless current.state == 'ATTACH_PENDING'

      message = scope.account.messages.lock.find(current.message_id)
      receipt = JrcBrokerHistoryReceipt.find(current.receipt_id)
      raise ArgumentError, 'historical_media_scope' unless message.inbox_id == scope.inbox.id && receipt.message_id == message.id &&
                                                           receipt.history_account_identity == current.history_account_identity

      attach!(current, message)
      current.update!(state: 'READY', last_error: nil)
    end
  end

  def retry_intent!(id)
    # Durable retry obligation, including the COMMIT -> enqueue gap. The scheduler
    # retries by intent ID only, never by credential, URL or customer payload.
    JrcBrokerHistoryMedia.where(id: id, state: 'ATTACH_PENDING').update_all( # rubocop:disable Rails/SkipsModelValidations
      ['attempts=attempts+1,last_error=?,next_attempt_at=?', 'JRC_HISTORY_MEDIA_RETRY', 1.minute.from_now]
    )
  end

  # The attachment and blob link are written together without live callbacks.
  # Database constraints and the locked immutable intent validate this write.
  # rubocop:disable Rails/SkipsModelValidations
  def attach!(intent, message)
    # Avoid Attachment/ActiveStorage callbacks: backfill must not emit scans,
    # analysis, notifications, bots or outbound messages.
    rows = Attachment.where(account_id: message.account_id, message_id: message.id).lock.to_a
    raise ArgumentError, 'historical_media_ambiguous' if rows.size > 1

    attachment = rows.first
    if attachment
      raise ArgumentError, 'historical_media_conflict' unless attachment.file.blob&.id == intent.blob_id
    else
      insert_attachment!(intent, message)
    end
  end

  def insert_attachment!(intent, message)
    file_type = Attachment.file_types.fetch(JrcBroker::HistorySyncMedia::TYPES.fetch(intent.descriptor.fetch('media_type')))
    row = Attachment.insert_all!([{ account_id: message.account_id, message_id: message.id, file_type: file_type,
                                    created_at: message.created_at, updated_at: message.created_at }], returning: %w[id])
    ActiveStorage::Attachment.insert_all!([{ name: 'file', record_type: 'Attachment', record_id: row.rows.first.first,
                                             blob_id: intent.blob_id, created_at: message.created_at }])
  end
  # rubocop:enable Rails/SkipsModelValidations
end
