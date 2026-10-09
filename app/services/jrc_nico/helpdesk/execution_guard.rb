class JrcNico::Helpdesk::ExecutionGuard
  def self.authorize!(access, command)
    return true unless command

    stored = JrcNico::Helpdesk::Approval.find_by(account_id: access.account.id, command_id: command.id)
    stamp = command.execution_context['helpdesk_event_id']
    return true unless stamp || stored

    new(access, command, stamp).authorize!
  end

  def initialize(access, command, stamp)
    @context = JrcNico::Helpdesk::Context.new(access.membership)
    @command = command
    @stamp = stamp
    @approval = JrcNico::Helpdesk::Approval.find_by!(account: @context.account, command: command, approver: @context.member)
  end

  def authorize!
    validate_state!
    event = @context.event(@approval.event_id)
    ticket = @context.ticket(event.ticket_id)
    raise Pundit::NotAuthorizedError unless event.policy_version.reload.eligible?(ticket, @context.member)
    raise Pundit::NotAuthorizedError unless @approval.scope == expected_scope(event, ticket)

    validate_digest!(event)
    JrcNico::Helpdesk::ActionPreview.new(context: @context, event: event, group_scope: @approval.scope['group'])
      .validate!(@command.tool, @command.arguments)
    true
  end

  private

  def validate_state!
    raise Pundit::NotAuthorizedError unless @stamp == @approval.event_id
    raise Pundit::NotAuthorizedError unless @approval.state == 'executing' && @approval.approved_at && @approval.expires_at > Time.current
  end

  def expected_scope(event, ticket)
    { 'account_id' => @context.account.id, 'policy_version_id' => event.policy_version_id,
      'policy_digest' => event.policy_version.digest, 'ticket_id' => ticket.id, 'unit_id' => ticket.unit_id,
      'company_id' => ticket.company_id, 'approver_id' => @context.member.id, 'expires_at' => @approval.expires_at.iso8601(6) }
      .tap { |scope| scope['group'] = @approval.scope['group'] if @approval.scope['group'] }
  end

  def validate_digest!(event)
    digest = JrcNico::Helpdesk::Definition.digest('event_id' => event.id, 'tool' => @command.tool,
                                                  'arguments' => @command.arguments, 'scope' => @approval.scope)
    raise Pundit::NotAuthorizedError unless ActiveSupport::SecurityUtils.secure_compare(digest, @approval.payload_digest)
  end
end
