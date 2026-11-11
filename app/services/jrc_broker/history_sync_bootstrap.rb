require 'active_support/core_ext/digest/uuid'

# Invoked under the V2 service's account, destination and identity locks.
class JrcBroker::HistorySyncBootstrap
  INDIVIDUAL = /\A(?:[1-9][0-9]{7,14}@s\.whatsapp\.net|[0-9]{1,30}@lid)\z/
  GROUP = /\A[0-9]+(?:-[0-9]+)?@g\.us\z/

  def initialize(scope, input)
    @scope = scope
    @input = input
    @recipient = input.fetch('recipient')
  end

  def call
    validate_recipient!
    key = phone || identifier
    JrcBroker::HistorySyncV2.lock_key("jrc-history:#{@scope.account.id}:contact:#{key}")
    contact = find_contact
    route = find_route(contact)
    conversation = find_conversation(contact, route)
    assert_conversation_owner!(conversation)
    { contact: contact, conversation: conversation, recipient: @recipient }
  end

  private

  def assert_conversation_owner!(conversation)
    previous = JrcBrokerHistoryReceipt.where(conversation_id: conversation.id)
    if previous.where.not(history_account_identity: @input.fetch('history_account_identity')).exists? ||
       previous.where.not(integration_id: @input.fetch('integration_id')).exists?
      raise ArgumentError, 'historical_conversation_owner_changed'
    end
  end

  def find_route(contact)
    routes = ContactInbox.where(contact_id: contact.id, inbox_id: @scope.inbox.id).order(:id).lock.limit(2).to_a
    raise ArgumentError, 'historical_route_ambiguous' if routes.size > 1

    routes.first || insert(ContactInbox, contact_id: contact.id, inbox_id: @scope.inbox.id,
                                         source_id: route_source_id, pubsub_token: SecureRandom.hex(32))
  end

  def route_source_id
    return "jrc-group-#{@recipient.fetch('group_scope')}" if @recipient['kind'] == 'GROUP'

    "jrc-#{@input.fetch('broker_contact_id')}"
  end

  def validate_recipient!
    kind = @recipient['kind']
    keys = { 'GROUP' => %w[kind jid name group_scope], 'INDIVIDUAL' => %w[kind jid name] }.fetch(kind) { raise ArgumentError, 'historical_recipient' }
    valid = @recipient.keys.sort == keys.sort && recipient_name_valid? && recipient_jid_valid?(kind)
    raise ArgumentError, 'historical_recipient' unless valid
    return unless kind == 'GROUP'

    raise ArgumentError, 'historical_recipient' unless /\A[a-f0-9]{64}\z/.match?(@recipient['group_scope'].to_s)
  end

  def recipient_name_valid?
    @recipient['name'].is_a?(String) && @recipient['name'].length.between?(1, 264)
  end

  def recipient_jid_valid?(kind)
    pattern = { 'GROUP' => GROUP, 'INDIVIDUAL' => INDIVIDUAL }.fetch(kind)
    @recipient['jid'].is_a?(String) && @recipient['jid'].bytesize <= 128 && pattern.match?(@recipient['jid'])
  end

  def phone
    @recipient['kind'] == 'INDIVIDUAL' && @recipient['jid'].end_with?('@s.whatsapp.net') ? @recipient['jid'].split('@').first : nil
  end

  def identifier
    return "jrc-group-#{@recipient.fetch('group_scope')}" if @recipient['kind'] == 'GROUP'

    "jrc-#{@input.fetch('organization_id')}-#{@input.fetch('broker_contact_id')}"
  end

  def find_contact
    contact = @scope.account.contacts.lock.find_by(identifier: identifier)
    contact ||= contact_for_phone if phone
    return insert_contact unless contact

    valid = phone ? contact.phone_number.to_s.gsub(/\D/, '') == phone : private_recipient_matches?(contact)
    raise ArgumentError, 'historical_contact_changed' unless valid

    contact
  end

  def contact_for_phone
    matches = @scope.account.contacts.where("regexp_replace(phone_number,'[^0-9]','','g') = ?", phone).lock.limit(2).to_a
    raise ArgumentError, 'historical_contact_ambiguous' if matches.size > 1

    matches.first
  end

  def private_recipient_matches?(contact)
    identity = { 'jrc_broker_recipient_kind' => @recipient.fetch('kind'), 'jrc_broker_jid' => @recipient.fetch('jid') }
    if @recipient['kind'] == 'GROUP'
      identity['jrc_broker_group_scope'] = @recipient.fetch('group_scope')
      return false if ContactInbox.where(contact_id: contact.id).where.not(inbox_id: @scope.inbox.id).exists?
    end
    contact.phone_number.blank? && contact.identifier == identifier && contact.additional_attributes.slice(*identity.keys) == identity
  end

  def insert_contact
    attributes = { account_id: @scope.account.id, identifier: identifier, name: @recipient.fetch('name'), phone_number: phone && "+#{phone}",
                   additional_attributes: { jrc_broker_recipient_kind: @recipient.fetch('kind'), jrc_broker_jid: @recipient.fetch('jid') } }
    attributes[:additional_attributes][:jrc_broker_group_scope] = @recipient['group_scope'] if @recipient['kind'] == 'GROUP'
    insert(Contact, attributes)
  end

  def find_conversation(contact, route)
    conversations = @scope.account.conversations.where(inbox_id: @scope.inbox.id, contact_id: contact.id, contact_inbox_id: route.id).lock
    return conversations.find_by!(display_id: @input.fetch('conversation_id')) if @input['conversation_id']
    # A canonical live mapping must be supplied by the Broker. Never guess among
    # conversations belonging to a previous session/owner, even if only one exists.
    raise ArgumentError, 'historical_route_requires_mapping' if conversations.exists?

    insert_conversation(contact, route)
  end

  def insert_conversation(contact, route)
    identity = [@scope.account.id, @scope.inbox.id,
                *@input.fetch_values('organization_id', 'integration_id', 'history_account_identity', 'broker_conversation_id')].join(':')
    uuid = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, identity)
    insert(Conversation, account_id: @scope.account.id, inbox_id: @scope.inbox.id, contact_id: contact.id, contact_inbox_id: route.id,
                         uuid: uuid, status: Conversation.statuses.fetch('resolved'), last_activity_at: stamp,
                         additional_attributes: { jrc_broker_historical: true })
  end

  def insert(model, attributes)
    row = model.insert_all!([attributes.merge(created_at: stamp, updated_at: stamp)], returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
    model.find(row.rows.first.first)
  end

  def stamp
    Time.at(@input.fetch('occurred_at')).utc
  end
end
