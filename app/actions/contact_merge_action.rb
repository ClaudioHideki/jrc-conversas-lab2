class ContactMergeAction
  include Events::Types
  pattr_initialize [:account!, :base_contact!, :mergee_contact!]

  def perform
    validate_contacts if @account.feature_enabled?('jrc_customer_master')
    # This case happens when an agent updates a contact email in dashboard,
    # while the contact also update his email via email collect box
    return @base_contact if base_contact.id == mergee_contact.id

    ActiveRecord::Base.transaction do
      lock_contacts_for_merge
      if @account.feature_enabled?('jrc_customer_master')
        preserver = JrcCustomers::MergePreserver.new(account: @account, base: @base_contact, source: @mergee_contact,
                                                     actor: Current.user)
        preserver.call
      end
      merge_conversations
      merge_messages
      merge_contact_inboxes
      merge_contact_notes
      move_broker_history_receipts
      preserver&.assert_native_references_moved!
      merge_and_remove_mergee_contact
    end
    @base_contact
  end

  private

  def lock_contacts_for_merge
    validate_contacts
    @account.lock!
    @account.contacts.where(id: [@base_contact.id, @mergee_contact.id]).order(:id).lock.load
    @base_contact.reload
    @mergee_contact.reload
    groups = JrcBroker::GroupContactAccess.new(account: @account, user: nil)
    return unless groups.group?(@base_contact) || groups.group?(@mergee_contact)

    raise JrcCustomers::MergePreserver::Conflict, 'WhatsApp group identity cannot be merged with another recipient'
  end

  def validate_contacts
    return if belongs_to_account?(@base_contact) && belongs_to_account?(@mergee_contact)

    raise StandardError, 'contact does not belong to the account'
  end

  def belongs_to_account?(contact)
    @account.id == contact.account_id
  end

  def merge_conversations
    Conversation.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_contact_notes
    Note.where(contact_id: @mergee_contact.id, account_id: @mergee_contact.account_id).update(contact_id: @base_contact.id)
  end

  def move_broker_history_receipts
    receipts = JrcBrokerHistoryReceipt.where(account_id: @account.id, contact_id: @mergee_contact.id)
    moved = @account.conversations.where(contact_id: @base_contact.id).select(:id)
    if receipts.where.not(conversation_id: moved).exists?
      raise JrcCustomers::MergePreserver::Conflict, 'Historical receipt conversation was not moved'
    end

    # Explicit contact merge only. Facts, owners, message IDs and hashes stay immutable.
    receipts.update_all(contact_id: @base_contact.id) # rubocop:disable Rails/SkipsModelValidations
  end

  def merge_messages
    Message.where(sender: @mergee_contact).update(sender: @base_contact)
  end

  def merge_contact_inboxes
    ContactInbox.where(contact_id: @mergee_contact.id).update(contact_id: @base_contact.id)
  end

  def merge_and_remove_mergee_contact
    mergable_attribute_keys = %w[identifier name email phone_number additional_attributes custom_attributes]
    base_contact_attributes = base_contact.attributes.slice(*mergable_attribute_keys).compact_blank
    mergee_contact_attributes = mergee_contact.attributes.slice(*mergable_attribute_keys).compact_blank

    # attributes in base contact are given preference
    merged_attributes = mergee_contact_attributes.deep_merge(base_contact_attributes)

    @mergee_contact.reload.destroy!
    Rails.configuration.dispatcher.dispatch(CONTACT_MERGED, Time.zone.now, contact: @base_contact,
                                                                           tokens: [@base_contact.contact_inboxes.filter_map(&:pubsub_token)])
    @base_contact.update!(merged_attributes)
  end
end
