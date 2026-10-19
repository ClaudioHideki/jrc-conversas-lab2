require 'active_support/core_ext/digest/uuid'

# Only invoked under HistoryImport's current account/integration/inbox fences.
# Matches the native Intercom importer's callback-free insert strategy.
class JrcBroker::HistoryBootstrap
  KEYS = %w[organization_id integration_id broker_contact_id broker_conversation_id phone name occurred_at].freeze

  def initialize(inbox, input)
    @inbox = inbox
    @account = inbox.account
    @input = input
  end

  def call
    validate!
    lock_key("contact:#{@input.fetch('phone')}")
    contact = historical_contact
    route = historical_route(contact)
    conversation = find_conversation(contact, route)
    { contact_id: contact.id, source_id: route.source_id, conversation_id: conversation.display_id,
      broker_contact_id: @input.fetch('broker_contact_id'), broker_conversation_id: @input.fetch('broker_conversation_id') }
  end

  private

  def find_conversation(contact, route)
    identity = [@account.id, @inbox.id, @input.fetch('organization_id'), @input.fetch('integration_id'), @input.fetch('broker_conversation_id')]
    uuid = Digest::UUID.uuid_v5(Digest::UUID::URL_NAMESPACE, identity.join(':'))
    lock_key("conversation:#{uuid}")
    conversation = Conversation.lock.find_by(uuid: uuid) || historical_conversation(contact, route, uuid)
    unless conversation.account_id == @account.id && conversation.inbox_id == @inbox.id &&
           conversation.contact_id == contact.id && conversation.contact_inbox_id == route.id
      raise ArgumentError, 'historical_route_changed'
    end

    conversation
  end

  def validate!
    valid = @input.keys.sort == KEYS.sort && valid_ids? && valid_contact? && valid_time?
    raise ArgumentError, 'historical_bootstrap_request' unless valid
  end

  def valid_ids?
    %w[broker_contact_id broker_conversation_id].all? { |key| JrcBroker::HistoryImport::UUID.match?(@input[key].to_s) }
  end

  def valid_contact?
    @input['phone'].is_a?(String) && @input['phone'].match?(/\A[1-9][0-9]{7,14}\z/) &&
      @input['name'].is_a?(String) && @input['name'].length.between?(1, 160)
  end

  def valid_time?
    @input['occurred_at'].is_a?(Integer) && @input['occurred_at'].between?(0, Time.current.to_i)
  end

  def lock_key(key)
    connection = ActiveRecord::Base.connection
    value = connection.quote("jrc-history:#{@account.id}:#{key}")
    connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{value},0))")
  end

  def historical_contact
    identifier = "jrc-#{@input.fetch('organization_id')}-#{@input.fetch('broker_contact_id')}"
    contact = @account.contacts.lock.find_by(identifier: identifier)
    unless contact
      matches = @account.contacts.where("regexp_replace(phone_number,'[^0-9]','','g') = ?", @input.fetch('phone')).lock.limit(2).to_a
      raise ArgumentError, 'historical_contact_ambiguous' if matches.size > 1

      contact = matches.first
    end
    contact ||= insert_contact(identifier)
    raise ArgumentError, 'historical_contact_changed' unless contact.phone_number.to_s.gsub(/\D/, '') == @input.fetch('phone')

    contact
  end

  def insert_contact(identifier)
    insert(Contact, { account_id: @account.id, identifier: identifier, phone_number: "+#{@input.fetch('phone')}", name: @input.fetch('name') })
  end

  def historical_route(contact)
    existing = ContactInbox.where(contact_id: contact.id, inbox_id: @inbox.id).order(:id).lock.limit(2).to_a
    raise ArgumentError, 'historical_route_ambiguous' if existing.size > 1
    return existing.first if existing.one?

    insert(ContactInbox, { contact_id: contact.id, inbox_id: @inbox.id,
                           source_id: "jrc-#{@input.fetch('broker_contact_id')}", pubsub_token: SecureRandom.hex(32) })
  end

  def historical_conversation(contact, route, uuid)
    insert(Conversation, { account_id: @account.id, inbox_id: @inbox.id, contact_id: contact.id, contact_inbox_id: route.id,
                           uuid: uuid, status: Conversation.statuses.fetch('pending'), last_activity_at: stamp,
                           additional_attributes: { jrc_broker_historical: true } })
  end

  def insert(model, attributes)
    # Validated immutable history only: native callbacks would trigger live automation.
    row = model.insert_all!([attributes.merge(created_at: stamp, updated_at: stamp)], returning: %w[id]) # rubocop:disable Rails/SkipsModelValidations
    model.find(row.rows.first.first)
  end

  def stamp
    Time.at(@input.fetch('occurred_at')).utc
  end
end
