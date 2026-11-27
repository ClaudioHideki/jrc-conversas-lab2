# frozen_string_literal: true

# Explicit current-user intake through the existing Service Desk workflow.
# No provider operation, automatic rule, parallel Ticket or new permission.
class JrcContactCenter::RecordingTicketIntake
  def initialize(account:, member:)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id

    @account = account
    @member = member
  end

  def call(recording_id:, unit_id:, attributes:, idempotency_key:, **options)
    with_source(recording_id) do |record, call, contact|
      raise ArgumentError unless JrcServiceDesk::Input.id(attributes.fetch('requester_id')) == contact.id

      create_ticket(record, call, { unit_id: unit_id, attributes: attributes, request_key: idempotency_key }, options)
    end
  end

  def preview(recording_id)
    with_source(recording_id) do |record, call, contact|
      context = JrcServiceDesk::OperationalContext.new(user_context)
      unit = authorized_unit!(context, call)
      { contract_version: 1, account_id: @account.id.to_s, user_id: @member.user_id.to_s, recording_id: record.id.to_s,
        call_session_id: call.id.to_s, call_id: call.external_session_id,
        contact_id: contact.id.to_s, service_desk_unit_id: unit.id.to_s }
    end
  end

  private

  def with_source(recording_id)
    source = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :recordings_listen)
    source.with_record(recording_id) do |record, call|
      authorize_operation!
      raise Pundit::NotAuthorizedError unless call.contact_id

      directory = JrcCustomers::ContactDirectory.new(account: @account, actor: @member.user)
      directory.with_locked_contact(call.contact_id) do |contact|
        authorize_contact!(call.reload, contact)
        yield record, call, contact
      end
    end
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
    identified = data[:status] == 'identified' && data[:identity_source] == 'call_contact_link' &&
                 data.dig(:directory, :contact_id) == contact.id.to_s && call.contact_id == contact.id
    raise Pundit::NotAuthorizedError unless identified
  end

  def create_ticket(record, call, input, options)
    context = JrcServiceDesk::OperationalContext.new(user_context)
    unit = authorized_unit!(context, call, input.fetch(:unit_id))
    key = JrcServiceDesk::Input.request_key(input.fetch(:request_key))
    reject_cross_unit_replay!(unit, key)
    raise ArgumentError if options[:internal_request] == true

    JrcServiceDesk::CreateTicketWorkflowService.new(user_context: context.to_h).call(
      unit_id: unit.id, attributes: input.fetch(:attributes), idempotency_key: key,
      **options, recording_origin: origin(record, call)
    )
  end

  def authorized_unit!(context, call, identifier = nil)
    raise Pundit::NotAuthorizedError unless context.native_operator? && context.capability?(:tickets_create) && context.capability?(:customers_view)

    mapped_id = mapped_unit_id(call)
    unit = context.unit_scope.find(identifier ? JrcServiceDesk::Input.id(identifier) : mapped_id)
    raise JrcServiceDesk::IdempotencyConflict unless mapped_id == unit.id

    unit
  end

  def mapped_unit_id(call)
    raise ArgumentError unless call.current_unit

    scope = call.current_unit.settings
    business = @account.jrc_crm_business_units.where(active: true).lock('FOR SHARE').find(JrcServiceDesk::Input.id(scope['business_unit_id']))
    raise Pundit::NotAuthorizedError unless business.company_id == JrcServiceDesk::Input.id(scope['issuer_company_id'])

    JrcServiceDesk::Input.id(business.settings['service_desk_unit_id'])
  end

  # Historical actor keys are inspected only to reject a duplicate in another unit.
  # This does not return the prior ticket or grant access to its contents.
  def reject_cross_unit_replay!(unit, key)
    actors = JrcServiceDesk::UnitMembership.where(account_id: @account.id, account_user_id: @member.id).select(:id)
    units = JrcServiceDesk::Ticket.where(account_id: @account.id, created_by_membership_id: actors, idempotency_key: key).limit(2).pluck(:unit_id)
    raise JrcServiceDesk::IdempotencyConflict unless units.empty? || units == [unit.id]
  end

  def origin(record, call)
    { 'schema_version' => 1, 'recording_id' => record.id, 'call_session_id' => call.id, 'call_id' => call.external_session_id,
      'contact_id' => call.contact_id,
      'unit_id' => call.current_unit_id, 'queue_id' => call.current_queue_id,
      'issuer_company_id' => JrcServiceDesk::Input.id(call.current_unit.settings['issuer_company_id']),
      'business_unit_id' => JrcServiceDesk::Input.id(call.current_unit.settings['business_unit_id']) }
  end
end
