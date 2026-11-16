class Internal::RemoveStaleContactInboxesService
  def perform
    return unless remove_stale_contact_inbox_job_enabled?

    time_period = 90.days.ago
    contact_inboxes_to_delete = stale_contact_inboxes(time_period)

    log_stale_contact_inboxes_deletion(contact_inboxes_to_delete, time_period)

    contact_inboxes_to_delete.find_in_batches(batch_size: 10_000) do |group|
      accounts_by_inbox = Inbox.where(id: group.map(&:inbox_id)).pluck(:id, :account_id).to_h
      by_account = group.group_by { |link| accounts_by_inbox[link.inbox_id] }
      by_account.keys.compact.sort.each do |account_id|
        Account.transaction do
          # Serialize with LIVE/V2 admission before rechecking the selected IDs.
          # Keep the transaction bounded to one Account and one batch.
          Account.lock.find(account_id)
          ContactInbox.stale_without_conversations(time_period)
                      .where(id: by_account.fetch(account_id).map(&:id), inbox_id: Inbox.where(account_id: account_id).select(:id))
                      .delete_all
        end
      end
    end
  end

  private

  def remove_stale_contact_inbox_job_enabled?
    job_status = ENV.fetch('REMOVE_STALE_CONTACT_INBOX_JOB_STATUS', false)
    return false unless ActiveModel::Type::Boolean.new.cast(job_status)

    true
  end

  def stale_contact_inboxes(time_period)
    ContactInbox.stale_without_conversations(time_period)
  end

  def log_stale_contact_inboxes_deletion(contact_inboxes, time_period)
    count = contact_inboxes.count
    Rails.logger.info "Deleting #{count} stale contact inboxes older than #{time_period}"

    # Log the SQL query without executing it
    sql_query = contact_inboxes.to_sql
    Rails.logger.info("SQL Query: #{sql_query}")
  end
end
