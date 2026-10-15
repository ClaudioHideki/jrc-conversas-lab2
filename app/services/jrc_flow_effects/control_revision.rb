class JrcFlowEffects::ControlRevision
  TRIGGERS = %w[jrc_effect_conversation_control jrc_effect_message_control jrc_effect_contact_inbox_control
                jrc_effect_contact_control jrc_effect_inbox_control jrc_effect_receipt_immutable].freeze

  def self.available?
    installed = ActiveRecord::Base.connection.select_values(<<~SQL.squish)
      SELECT t.tgname FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = current_schema() AND t.tgenabled IN ('O', 'A') AND NOT t.tgisinternal
        AND t.tgname IN ('jrc_effect_conversation_control', 'jrc_effect_message_control', 'jrc_effect_contact_inbox_control',
                        'jrc_effect_contact_control', 'jrc_effect_inbox_control', 'jrc_effect_receipt_immutable')
    SQL
    installed.sort == TRIGGERS.sort
  end

  def self.snapshot(conversation)
    # MVCC reads under the Conversation lock; never invert the routing-trigger lock order.
    inbox = Inbox.find(conversation.inbox_id)
    contact = Contact.find(conversation.contact_id)
    route = ContactInbox.find(conversation.contact_inbox_id)
    same = inbox.account_id == conversation.account_id && contact.account_id == conversation.account_id &&
           route.inbox_id == inbox.id && route.contact_id == contact.id
    raise ArgumentError, 'destination_changed' unless same

    { 'account_id' => conversation.account_id, 'inbox_id' => inbox.id, 'remote_conversation_id' => conversation.display_id,
      'remote_contact_id' => contact.id, 'contact_inbox_id' => route.id, 'routing_source_hash' => Digest::SHA256.hexdigest(route.source_id),
      'control_revision' => JrcFlowEffects::Request.integer(conversation.jrc_effect_control_revision, zero: true) }
  end
end
