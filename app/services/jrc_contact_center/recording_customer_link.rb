# frozen_string_literal: true

# Initial explicit linkage only. Native account/call authority and master coverage
# remain authoritative; a matching telephone or a request ID never grants access.
class JrcContactCenter::RecordingCustomerLink
  COMMENT = 'jrc_contact_center_call_contact_link_v1'

  def initialize(account:, member:)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id

    @account = account
    @member = member
  end

  def preview(recording_id)
    with_source(recording_id) do |record, call, _directory|
      identity(record, call).merge(can_link: call.contact_id.nil?, already_linked: call.contact_id.present?)
    end
  end

  def call(recording_id, input)
    with_source(recording_id) do |record, call, directory|
      call.with_lock do
        validate_source!(record, call, input)
        directory.with_locked_contact(input.fetch('contact_id')) do |contact|
          validate_company!(call, contact)
          persist!(record, call, contact)
        end
        identity(record, call).merge(contact_id: call.contact_id.to_s)
      end
    end
  end

  private

  def with_source(recording_id)
    reader = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :recordings_listen)
    reader.with_record(recording_id) do |record, call|
      context = { account: @account, account_user: @member, user: @member.user }
      raise Pundit::NotAuthorizedError unless JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?

      directory = JrcCustomers::ContactDirectory.new(account: @account, actor: @member.user)
      directory.authorize!
      yield record, call, directory
    end
  end

  def identity(record, call)
    { contract_version: 1, account_id: @account.id.to_s, user_id: @member.user_id.to_s,
      recording_id: record.id.to_s, call_session_id: call.id.to_s,
      call_id: call.external_session_id, lock_version: call.lock_version }
  end

  def validate_source!(record, call, input)
    exact = input['confirm'] == true && input['call_session_id'] == call.id.to_s && input['call_id'] == record.external_unique_id
    raise ArgumentError unless exact

    JrcServiceDesk::Input.id(input.fetch('contact_id'))
    validate_version!(call, input.fetch('lock_version'))
  end

  def validate_version!(call, version)
    raise ArgumentError unless version.is_a?(Integer) && version >= 0

    conflict! if call.contact_id.present? || call.lock_version != version
  end

  def validate_company!(call, contact)
    conflict! if call.company_id.present? && call.company_id != contact.company_id
  end

  def persist!(record, call, contact)
    previous = call.attributes.slice('contact_id', 'company_id', 'lock_version')
    call.update!(contact: contact, company_id: contact.company_id)
    audit!(record, call, previous)
  end

  def audit!(record, call, previous)
    scope = JrcContactCenter::RecordingAudit.scope_fields(call)
    Audited.audit_class.create!(
      auditable: call, associated: @account, user: @member.user, action: 'update', comment: COMMENT,
      audited_changes: { 'schema_version' => 1, 'operation' => 'initial_contact_link', 'recording_id' => record.id.to_s,
                         'before' => previous, 'after' => call.attributes.slice('contact_id', 'company_id', 'lock_version') }.merge(scope)
    )
  end

  def conflict!
    raise JrcContactCenter::OperationError.new('recording_contact_link_conflict', status: :conflict)
  end
end
