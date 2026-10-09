# frozen_string_literal: true

# A server-only provenance bridge. Native services still enforce every capability and version.
class JrcServiceDesk::NativeMutationOrigin
  def initialize(context:, ticket:, tool:, attributes:, command: nil)
    @context = context
    @ticket = ticket
    @tool = tool
    @attributes = attributes.stringify_keys
    @command = command
  end

  def call(expected_lock_version: nil, request_key: nil)
    @version = expected_lock_version
    @request_key = request_key
    value = { 'schema' => 'native-operation-v1', 'kind' => 'operator', 'account_user_id' => @context.account_user.id }
    return value unless @command

    verify_command!
    value.merge('kind' => 'operator_assisted_nico', 'command_id' => @command.id, 'session_id' => @command.session_id,
                'tool' => @tool, 'request_id' => @command.request_id, 'input_digest' => input_digest(@command.arguments))
  end

  private

  def verify_command!
    raise Pundit::NotAuthorizedError unless @command.is_a?(JrcNico::Command) && @command.persisted?

    @command.reload
    verify_session!
    verify_executing_command!
    verify_authorization!
    verify_arguments!
  end

  def verify_session!
    session = @command.session.reload
    valid = session.account_id == @ticket.account_id && session.account_id == @context.account.id && session.user_id == @context.user.id
    raise Pundit::NotAuthorizedError unless valid
  end

  def verify_executing_command!
    valid = @command.status == 'executing' && @command.approved_at.present? && @command.tool == @tool && @command.request_id.present?
    raise Pundit::NotAuthorizedError unless valid
  end

  def verify_authorization!
    authority = @command.execution_context.fetch('authorization', {})
    valid = authority['source'] == 'operator' && authority['user_id'] == @context.user.id
    valid &&= authority['request_id'] == @command.request_id if authority['mode'] == 'explicit_request'
    raise Pundit::NotAuthorizedError unless valid
  end

  def verify_arguments!
    args = @command.arguments
    raise Pundit::NotAuthorizedError unless args['ticket_id'] == @ticket.id
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::CanonicalJson.dump(args.slice(*fields)) == JrcServiceDesk::CanonicalJson.dump(@attributes)

    if @tool == 'update_service_ticket'
      raise Pundit::NotAuthorizedError unless args['expected_lock_version'] == JrcServiceDesk::Input.version(@version)
    elsif @tool == 'transition_service_ticket'
      raise Pundit::NotAuthorizedError unless @request_key == "nico_#{@command.id}_#{@command.request_id}"
    else
      raise Pundit::NotAuthorizedError
    end
  end

  def fields
    return JrcServiceDesk::UpdateTicketService::FIELDS + ['company_id'] if @tool == 'update_service_ticket'

    JrcServiceDesk::LifecycleTransitionService::FIELDS
  end

  def input_digest(args)
    values = args.slice('ticket_id', *fields)
    values['expected_lock_version'] = args['expected_lock_version']
    JrcServiceDesk::CanonicalJson.digest(values)
  end
end
