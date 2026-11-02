class JrcCampaigns::BrokerMediaUpload
  def self.call(file)
    # Match create_and_upload!, but retain the new blob before storage can fail.
    # This is called inside the sender's transaction, possibly joined to a caller lock.
    blob = ActiveStorage::Blob.create_after_unfurling!(**file)
    blob.class.connection.add_transaction_record(new(blob))
    blob.upload_without_unfurling(file.fetch(:io))
    blob
  end

  def initialize(blob)
    @blob = blob
  end

  # Rails 7.1 transaction-record hooks follow the outermost commit/rollback.
  # No model callbacks are needed; never delete a blob after a successful commit.
  def trigger_transactional_callbacks?
    false
  end

  def before_committed!; end

  def committed!(**); end

  def rolledback!(**)
    # The database row was rolled back, so purge cannot locate it. Delete only
    # the server-generated storage key owned by this newly created blob.
    @blob.delete
  end
end
