# frozen_string_literal: true

require 'digest'

# Native recording, customer directory and Relationship portfolio authority;
# no customer, portfolio, contact or destination privilege is created here.
class JrcContactCenter::RecordingRelationshipScope
  def initialize(account:, member:)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id

    @account = account
    @member = member
    @actor_id = member.user_id
  end

  def with_origin(recording_id, lock: false)
    recording_id = JrcServiceDesk::Input.id(recording_id)
    source = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :recordings_listen)
    source.with_record(recording_id) do |record, call|
      raise Pundit::NotAuthorizedError unless @member.user_id == @actor_id

      lock_origin!(record, call) if lock
      authorize_operation!
      raise Pundit::NotAuthorizedError unless call.contact_id

      directory = JrcCustomers::ContactDirectory.new(account: @account, actor: @member.user)
      with_directory_contact(directory, call.contact_id, lock) do |contact|
        authorize_contact!(call.reload, contact)
        yield record, call, contact, relationship_context!
      end
    end
  end

  def assignments(context, call, contact)
    settings = call.current_unit&.settings || {}
    business = @account.jrc_crm_business_units.where(active: true).find(JrcServiceDesk::Input.id(settings['business_unit_id']))
    raise Pundit::NotAuthorizedError unless business.company_id == JrcServiceDesk::Input.id(settings['issuer_company_id'])

    rows = context.assignments.where(business_unit_id: [nil, business.id])
    selected = rows.where(contact_id: contact.id)
    contact.company_id ? selected.or(rows.where(company_id: contact.company_id)) : selected
  end

  def preview(recording_id, page: 1)
    number = JrcServiceDesk::Input.version(page).clamp(1, 1_000_000)
    with_origin(recording_id) do |record, call, contact, context|
      rows = assignments(context, call, contact)
      total = rows.count
      preview_identity(record, call, contact, context).merge(
        items: assignment_choices(context, rows, number), meta: { page: number, per_page: 20, total: total, pages: (total / 20.0).ceil }
      )
    end
  end

  def origin(record, call, contact, context)
    settings = call.current_unit.settings
    { 'schema_version' => 1, 'account_id' => @account.id, 'recording_id' => record.id, 'call_session_id' => call.id,
      'contact_id' => contact.id, 'customer_company_id' => contact.company_id,
      'unit_id' => call.current_unit_id, 'queue_id' => call.current_queue_id,
      'issuer_company_id' => JrcServiceDesk::Input.id(settings['issuer_company_id']),
      'business_unit_id' => JrcServiceDesk::Input.id(settings['business_unit_id']),
      'source_sha256' => Digest::SHA256.hexdigest([record.external_unique_id, call.external_session_id].to_json),
      'time_zone' => context.formatting.fetch(:timeZone) }
  end

  private

  def preview_identity(record, call, contact, context)
    { contract_version: 1, account_id: @account.id.to_s, user_id: @member.user_id.to_s, recording_id: record.id.to_s,
      call_session_id: call.id.to_s, call_id: call.external_session_id, contact_id: contact.id.to_s,
      origin_revision: Digest::SHA256.hexdigest(origin(record, call, contact, context).to_json),
      time_zone: context.formatting.fetch(:timeZone) }
  end

  def assignment_choices(context, rows, number)
    rows.order(:id).offset((number - 1) * 20).limit(20).map do |row|
      { id: row.id.to_s, label: row.label.to_s, can_work: JrcRelationship::AssignmentPolicy.new(context.to_h, row).update? }
    end
  end

  def relationship_context!
    context = JrcRelationship::Context.new(@member)
    crm = JrcContactCenter::EndingActions::ConfiguredNativeAction.crm_available?(@member)
    raise Pundit::NotAuthorizedError unless context.policy.manage? && crm

    context
  end

  def with_directory_contact(directory, id, lock, &)
    return directory.with_locked_contact(id, &) if lock

    yield directory.find(id)
  end

  def lock_origin!(record, call)
    record.lock!
    call.lock!
    reader = JrcContactCenter::RecordedCalls.new(account: @account, member: @member)
    _, current_call = reader.find(record.id, action: :listen)
    raise ArgumentError, 'A origem da chamada mudou. Atualize antes de continuar.' unless current_call.id == call.id
  end

  def user_context
    { account: @account, account_user: @member, user: @member.user }
  end

  def authorize_operation!
    policy = JrcContactCenter::ModulePolicy.new(user_context, :contact_center)
    raise Pundit::NotAuthorizedError unless policy.operate?
  end

  def authorize_contact!(call, contact)
    data = JrcContactCenter::CustomerContext.new(account: @account, user_context: user_context).for_call(call)
    valid = call.contact_id == contact.id && call.company_id == contact.company_id &&
            data[:status] == 'identified' && data[:identity_source] == 'call_contact_link' &&
            data.dig(:directory, :contact_id) == contact.id.to_s
    raise Pundit::NotAuthorizedError unless valid
  end
end
