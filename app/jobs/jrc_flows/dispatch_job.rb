class JrcFlows::DispatchJob < ApplicationJob
  queue_as :default

  def perform(account_id, conversation_id, event_name, event_key, message_id = nil, label = nil, flow_id = nil)
    account = Account.find_by(id: account_id)
    return unless JrcFlows::Access.enabled?(account)

    conversation = account.conversations.find_by(id: conversation_id)
    return unless conversation

    message = conversation.messages.find_by(id: message_id) if message_id
    return if message_id && (!message || !message.incoming? || message.private? || message.content_attributes.to_h['jrc_flow_run_id'])

    run = nil
    conversation.with_lock do
      run = JrcFlowRun.live.find_by(conversation: conversation)
      unless run
        candidates = JrcFlow.active.where(account: account, connection_id: nil).order(:id)
        candidates = candidates.where(id: flow_id) if flow_id
        flow = candidates.detect { |candidate| eligible?(candidate, conversation, event_name, message, label) }
        return unless flow
        return if flow.runs.exists?(event_key: event_key)

        variables = {
          'message' => message&.content.to_s.first(10_000),
          'contact.name' => conversation.contact.name.to_s,
          'contact.email' => conversation.contact.email.to_s,
          'contact.phone_number' => conversation.contact.phone_number.to_s,
          'conversation.id' => conversation.display_id.to_s,
          'inbox.name' => conversation.inbox.name
        }
        run = flow.runs.create!(account: account, conversation: conversation, event_key: event_key,
                               graph: flow.graph, settings: flow.settings.merge('_flow_version' => flow.lock_version), variables: variables,
                               node_id: flow.graph.fetch('nodes').find { |n| n['type'] == 'start' }.fetch('id'),
                               last_message_id: message&.id || 0)
        message = nil
      end
    end
    JrcFlows::Runner.new(run).perform(message: message) if message || run.status == 'running'
  end

  private

  def eligible?(flow, conversation, event, message, label)
    settings = flow.settings
    return false unless settings['trigger'] == event
    return false unless flow.account.account_users.exists?(user_id: flow.created_by_id, role: 'administrator')
    return false if event == 'stage_changed' && settings['stage_id'].to_s != label.to_s
    return false unless Array(settings['inbox_ids']).map(&:to_i).include?(conversation.inbox_id)
    return false if conversation.assignee_agent_bot_id.present? || JrcFlows::Access.inbox_bot_owned?(conversation)
    return false if settings.fetch('pause_on_agent', true) && conversation.assignee_id.present?
    return false if settings.fetch('pause_on_team', false) && conversation.team_id.present?
    return false if event == 'label_added' && settings['label'] != label
    return false if settings['keyword'].present? && !message&.content.to_s.downcase.include?(settings['keyword'].downcase)
    if flow.kind == 'chatbot'
      previous = flow.runs.where(conversation: conversation).order(:id).last
      return false if previous && !(settings.fetch('restart_on_resolve', true) && previous.reset_at)
    end
    within_hours?(settings)
  end

  def within_hours?(settings)
    JrcFlows::BusinessHours.open?(settings)
  end
end
