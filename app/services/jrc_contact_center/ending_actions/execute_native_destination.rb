# frozen_string_literal: true

# Internal schema-2 adapter selector. The caller owns the original-actor
# transaction and the immutable attempt; this is neither an API nor a grant.
# Explicit operations only select existing native commands, never a class name
# or arbitrary attributes supplied by an HTTP caller.
class JrcContactCenter::EndingActions::ExecuteNativeDestination
  def initialize(account:, member:, origin:, attempt:)
    @account = account
    @member = member
    @origin = origin
    @attempt = attempt
  end

  def call(action:, readiness:)
    raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction' unless Account.connection.transaction_open?

    normalized = JrcContactCenter::EndingActions::DestinationOperationDefinition.new.call(action)
    raise JrcContactCenter::OperationError, 'ending_attempt_identity_mismatch' unless normalized == action

    parameters = normalized.fetch('parameters')
    operation = parameters.fetch('operation') { default_operation(normalized.fetch('kind')) }
    actual = [normalized.fetch('kind'), operation, readiness.id, readiness.account_id]
    expected = [@attempt.destination_kind, @attempt.operation, @attempt.readiness_id, @account.id]
    raise JrcContactCenter::OperationError, 'ending_attempt_identity_mismatch' unless actual == expected

    execute!(parameters.key?('operation') ? parameters.fetch('parameters') : parameters, readiness)
  end

  private

  def default_operation(kind)
    { 'project_task' => 'create_task', 'crm' => 'create_lead', 'service_desk' => 'create_ticket' }.fetch(kind)
  end

  def execute!(parameters, readiness)
    case @attempt.operation
    when 'create_task' then project_task(parameters, readiness)
    when 'create_lead' then crm_lead
    when 'create_activity' then crm_activity(parameters)
    when 'create_ticket' then service_desk_create(parameters)
    when 'update_ticket' then service_desk_update(parameters)
    else raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable'
    end
  end

  def project_task(parameters, readiness)
    JrcContactCenter::EndingActions::ProjectTaskDestination.new(account: @account, member: @member).call(
      parameters: parameters, trigger_at: @attempt.triggered_at, timezone: readiness.source_timezone,
      correlation_id: @attempt.effect_key
    )
  end

  def crm_lead
    # Native corporate/owner policy remains authoritative, including refusal
    # of an unscoped new Lead. This selector never invents a destination unit.
    JrcContactCenter::EndingActions::CrmLeadDestination.new(account: @account, member: @member).call(origin: @origin).fetch(:lead)
  end

  def crm_activity(parameters)
    JrcContactCenter::EndingActions::CrmActivityDestination.new(account: @account, member: @member).call(
      origin: @origin, parameters: parameters, trigger_at: @attempt.triggered_at
    )
  end

  def service_desk_create(parameters)
    JrcContactCenter::EndingActions::ServiceDeskTicketDestination.new(account: @account, member: @member).call(
      origin: @origin, parameters: parameters, request_key: @attempt.effect_key
    )
  end

  def service_desk_update(parameters)
    # The exact reviewed invocation revision remains strict. Neither this
    # selector nor a replay may silently refresh expected_lock_version.
    JrcContactCenter::EndingActions::ServiceDeskTicketUpdate.new(account: @account, member: @member).call(
      origin: @origin, parameters: parameters
    ).fetch(:ticket)
  end
end
