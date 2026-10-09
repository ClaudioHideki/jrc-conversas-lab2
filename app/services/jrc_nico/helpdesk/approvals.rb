class JrcNico::Helpdesk::Approvals
  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member)
  end

  def prepare(event_id:, tool:, arguments:, group_key: nil, input: {}, preview_digest: nil)
    event = @context.event(event_id)
    raise Pundit::NotAuthorizedError unless event.actor_id == @context.member.id

    @context.account.with_lock do
      event.with_lock do
        validate_policy!(event)
        group = group_scope(event, group_key, input, tool, arguments, preview_digest) if group_key
        JrcNico::Helpdesk::ActionPreview.new(context: @context, event: event, group_scope: group).validate!(tool, arguments)
        command = prepared_command(event, tool, arguments, group)
        existing = JrcNico::Helpdesk::Approval.find_by(account: @context.account, command: command)
        next existing if existing

        reject_executed_tool!(event, tool, group)
        create_approval!(event, command, group)
      end
    end
  end

  def approve(id:, payload_digest:)
    approval = find(id)
    should_execute = @context.account.with_lock do
      approval.with_lock do
        next false if %w[succeeded reconciled].include?(approval.state)
        raise ArgumentError, 'Unknown outcome requires reconciliation; retry is forbidden' if %w[unknown executing].include?(approval.state)
        raise ArgumentError, 'Approval is no longer pending' unless approval.state == 'pending'

        verify!(approval, payload_digest)
        approval.update!(state: 'executing', approved_at: Time.current)
        true
      end
    end
    return approval unless should_execute

    execute(approval)
  end

  def cancel(id:)
    approval = find(id)
    approval.with_lock do
      raise ArgumentError, 'An executing/unknown action cannot be cancelled as if it never happened' unless approval.state == 'pending'

      JrcNico::OperatorSession.new(account: @context.account, user: @context.member.user).cancel(approval.command)
      approval.update!(state: 'cancelled')
    end
    approval
  end

  def reconcile(id:, resource_type:, resource_id:)
    approval = find(id)
    @context.administrator!
    approval.with_lock do
      raise ArgumentError, 'Only an unknown outcome can be reconciled' unless approval.state == 'unknown'

      resources = Array(approval.command.result['resources']) + JrcNico::Notice.resources_for(approval.command)
      pair = [resource_type, resource_id]
      raise ArgumentError, 'Persisted native execution evidence is required; no success was inferred' unless resources.include?(pair)

      JrcNico::DomainAccess.authorize_resource!(@context.access, *pair)
      approval.update!(state: 'reconciled', reconciled_at: Time.current,
                       reconciliation: { 'resource_type' => resource_type, 'resource_id' => resource_id })
    end
    approval
  end

  private

  def prepared_command(event, tool, arguments, group)
    session = JrcNico::OperatorSession.new(account: @context.account, user: @context.member.user)
    session.ask(message: "HelpDesk #{event.rule_key}: #{tool}", request_id: request_id(event, tool, arguments, group),
                prepared: { 'tool' => tool, 'arguments' => arguments })
  end

  def reject_executed_tool!(event, tool, group)
    terminal = event.approvals.where(state: %w[succeeded reconciled executing unknown]).joins(:command)
    if group
      terminal = terminal.where("scope -> 'group' ->> 'group_key' = ?", group.fetch('group_key'))
      if terminal.where(state: %w[executing unknown]).exists?(jrc_nico_commands: { tool: tool })
        raise ArgumentError, 'An executing or unknown group attempt requires reconciliation'
      end
      limit = tool == 'add_service_ticket_note' ? 2 : 1
      raise ArgumentError, 'This group already reached its native action limit' if terminal.where(jrc_nico_commands: { tool: tool }).count >= limit

      return
    end
    raise ArgumentError, 'This event already executed that tool' if terminal.exists?(jrc_nico_commands: { tool: tool })
  end

  def create_approval!(event, command, group)
    command.update!(execution_context: command.execution_context.merge('helpdesk_event_id' => event.id))
    expires_at = Time.current + event.policy_version.definition.fetch('approval_ttl_seconds')
    scope = scope_for(event, group).merge('expires_at' => expires_at.iso8601(6))
    JrcNico::Helpdesk::Approval.create!(account: @context.account, command: command, event: event, approver: @context.member,
                                        scope: scope, payload_digest: payload_digest(event, command, scope), expires_at: expires_at)
  end

  def request_id(event, tool, arguments, group)
    parts = [event.id, tool, arguments]
    parts << group if group
    hex = JrcNico::Helpdesk::Definition.digest(parts)[0, 32]
    hex[12] = '4'
    hex[16] = ((hex[16].to_i(16) & 3) | 8).to_s(16)
    [hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12]].join('-')
  end

  def find(id)
    approval = JrcNico::Helpdesk::Approval.where(account: @context.account, approver: @context.member).find(id)
    @context.event(approval.event_id)
    approval
  end

  def scope_for(event, group = nil)
    ticket = @context.ticket(event.ticket_id)
    { 'account_id' => @context.account.id, 'policy_version_id' => event.policy_version_id, 'policy_digest' => event.policy_version.digest,
      'ticket_id' => ticket.id, 'unit_id' => ticket.unit_id, 'company_id' => ticket.company_id, 'approver_id' => @context.member.id }
      .tap { |scope| scope['group'] = group if group }
  end

  def payload_digest(event, command, scope)
    JrcNico::Helpdesk::Definition.digest('event_id' => event.id, 'tool' => command.tool, 'arguments' => command.arguments, 'scope' => scope)
  end

  def validate_policy!(event)
    ticket = @context.ticket(event.ticket_id)
    enabled = event.policy_version.definition.dig('rules', event.rule_key, 'enabled')
    raise Pundit::NotAuthorizedError unless event.policy_version.reload.eligible?(ticket, @context.member) && enabled
  end

  def verify!(approval, digest)
    validate_policy!(approval.event)
    verify_payload!(approval, digest)
    raise ArgumentError, 'Native command is no longer awaiting confirmation' unless approval.command.status == 'awaiting_confirmation'

    JrcNico::Helpdesk::ActionPreview.new(context: @context, event: approval.event, group_scope: approval.scope['group'])
      .validate!(approval.command.tool, approval.command.arguments)
    validate_limit!(approval.event.policy_version)
  end

  def verify_payload!(approval, digest)
    raise ArgumentError, 'Approval expired' unless approval.expires_at > Time.current
    raise Pundit::NotAuthorizedError unless approval.scope.except('expires_at') == scope_for(approval.event, approval.scope['group'])
    raise ArgumentError, 'Approval expiry changed' unless approval.scope['expires_at'] == approval.expires_at.iso8601(6)

    expected = payload_digest(approval.event, approval.command.reload, approval.scope)
    unless ActiveSupport::SecurityUtils.secure_compare(expected, approval.payload_digest) &&
           ActiveSupport::SecurityUtils.secure_compare(expected, digest.to_s)
      raise ArgumentError, 'Approval payload changed'
    end
  end

  def validate_limit!(policy)
    count = JrcNico::Helpdesk::Approval.where(account: @context.account).where('approved_at > ?', 1.hour.ago).count
    raise ArgumentError, 'Account hourly action limit reached' if count >= policy.definition.fetch('hourly_limit')
  end

  def execute(approval)
    command = JrcNico::OperatorSession.new(account: @context.account, user: @context.member.user).execute(approval.command)
    state = %w[succeeded failed unknown].include?(command.status) ? command.status : 'unknown'
    approval.update!(state: state)
    approval
  rescue StandardError
    state = approval.command.reload.status == 'failed' ? 'failed' : 'unknown'
    approval.update!(state: state)
    raise
  end

  def group_scope(event, key, input, tool, arguments, digest)
    JrcNico::Helpdesk::GroupActionPreview.new(context: @context, event: event, group_key: key, input: input)
      .approval_scope(tool: tool, arguments: arguments, preview_digest: digest)
  end
end
