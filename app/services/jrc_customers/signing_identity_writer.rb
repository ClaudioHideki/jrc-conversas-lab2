class JrcCustomers::SigningIdentityWriter
  class Changed < StandardError; end

  def initialize(account:, actor:)
    @account = account
    @actor = actor
    @directory = JrcCustomers::ContactDirectory.new(account: account, actor: actor)
  end

  def save!(contact_id:, personal_tax_identifier:, expected_revision:)
    @directory.with_locked_contact(contact_id) do |contact|
      record = JrcCustomers::SigningIdentity.find_or_initialize_by(account_id: @account.id, contact_id: contact.id)
      check_revision!(record, expected_revision)
      previous = record.persisted? ? record.serializable_hash : {}
      record.created_by = @actor if record.new_record?
      record.personal_tax_identifier = personal_tax_identifier
      record.revision += 1 if record.persisted?
      record.save!
      audit!(contact, previous, record.serializable_hash)
      record
    end
  end

  private

  def check_revision!(record, value)
    expected = Integer(value.to_s, 10)
    raise Changed, 'IDENTITY_CHANGED' unless expected == (record.persisted? ? record.revision : 0)
  rescue ArgumentError
    raise Changed, 'IDENTITY_CHANGED'
  end

  def audit!(contact, previous, current)
    JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: contact, event_type: 'customer_contact_updated',
                                from_value: previous, to_value: current,
                                metadata: { action: 'signing_identity_updated', signing_authority_verified: false })
  end
end
