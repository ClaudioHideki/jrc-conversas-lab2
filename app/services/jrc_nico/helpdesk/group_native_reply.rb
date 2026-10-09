# frozen_string_literal: true

# Human-approved public acknowledgement through the existing MessageBuilder/provider.
class JrcNico::Helpdesk::GroupNativeReply
  def self.authorize_result!(context, command)
    conversation = context.access.conversation(command.arguments.fetch('conversation_id'))
    message = conversation.messages.where(account_id: context.account.id).find(command.result.fetch('id'))
    valid = message.outgoing? && !message.private? && message.sender == context.member.user &&
            message.content == command.arguments.fetch('content')
    raise Pundit::NotAuthorizedError unless valid
  end

  def initialize(context:, event:, group_key:, input:)
    @context, @event, @group, @input = context, event, group_key, input
    @ticket = context.ticket(event.ticket_id)
  end

  def evidence!(value)
    return unless @input

    conversation = authorized_conversation
    value[:resources].concat([['Conversation', conversation.id], ['JrcNico::ServiceTicketConversations', @ticket.id]])
    value[:evidence] << { kind: 'native_customer_conversation', id: conversation.id, display_id: conversation.display_id,
                         inbox_id: conversation.inbox_id, contact_id: conversation.contact_id, contact_inbox_id: conversation.contact_inbox_id }
  end

  def candidate
    return unless @input

    conversation = authorized_conversation
    reason = 'native_messaging_window_closed' unless conversation.can_reply?
    reason = 'native_bot_or_flow_owned' if bot_owned?(conversation)
    { tool: 'send_message', arguments: arguments_for, blocked_reason: reason }
  end

  private

  def arguments_for
    raise Pundit::NotAuthorizedError unless @group == 'D2' && @event.rule_key == 'R10'

    values = @input.merge('private' => false)
    JrcNico::ToolCatalog.new(@context.access).validate!('send_message', values)
    values
  end

  def authorized_conversation
    arguments = arguments_for
    Pundit.authorize(@context.native.to_h, @ticket, :view_conversations?)
    conversation = @context.access.conversation(arguments.fetch('conversation_id'))
    raise Pundit::NotAuthorizedError unless matching_conversation?(conversation)

    conversation
  end

  def matching_conversation?(conversation)
    @ticket.ticket_conversations.exists?(account_id: @context.account.id, conversation_id: conversation.id) &&
      conversation.contact_id == @ticket.requester_id && @context.access.inbox_visible?(conversation.inbox) &&
      conversation.contact_inbox&.contact_id == @ticket.requester_id && conversation.contact_inbox&.inbox_id == conversation.inbox_id
  end

  def bot_owned?(conversation)
    conversation.assignee_agent_bot_id.present? || JrcFlows::Access.inbox_bot_owned?(conversation) ||
      JrcFlowRun.live.exists?(account_id: @context.account.id, conversation_id: conversation.id)
  end
end
