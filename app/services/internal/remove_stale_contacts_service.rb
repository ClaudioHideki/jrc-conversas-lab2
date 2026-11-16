class Internal::RemoveStaleContactsService
  pattr_initialize [:account!]

  def perform(batch_size = 1000)
    cutoff = 30.days.ago
    contacts_to_remove = @account.contacts.stale_without_conversations(cutoff)
    total_deleted = 0

    Rails.logger.info "[Internal::RemoveStaleContactsService] Starting removal of stale contacts for account #{@account.id}"

    contacts_to_remove.find_in_batches(batch_size: batch_size) do |batch|
      deleted_count = Account.transaction do
        # Broker admission holds FOR SHARE on this Account. A selected batch
        # may already be stale, so recheck eligibility after the exclusive lock.
        Account.lock.find(@account.id)
        contact_ids = Contact.where(account_id: @account.id).stale_without_conversations(cutoff)
                             .where(id: batch.map(&:id)).pluck(:id)
        ContactInbox.where(contact_id: contact_ids).delete_all
        Contact.where(account_id: @account.id, id: contact_ids).delete_all
      end
      total_deleted += deleted_count
      Rails.logger.info "[Internal::RemoveStaleContactsService] Deleted #{deleted_count} contacts (#{total_deleted} total) for account #{@account.id}"
    end
  end
end
