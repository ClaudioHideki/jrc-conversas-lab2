Rails.application.config.to_prepare do
  {
    AutomationRules::ActionService => JrcFlows::NativeResponderHooks::Rules,
    SendReplyJob => JrcFlows::NativeResponderHooks::Replies,
    WebhookJob => JrcFlows::NativeResponderHooks::MessageWebhooks,
    AgentBotListener => JrcFlows::NativeResponderHooks::BotListener,
    AgentBots::WebhookJob => JrcFlows::NativeResponderHooks::BotWebhook,
    Api::V1::Accounts::Conversations::MessagesController => JrcFlows::NativeResponderHooks::MessageActor,
    Api::V1::Accounts::Conversations::AssignmentsController => JrcFlows::NativeResponderHooks::AssignmentActor,
    Api::V1::Accounts::ConversationsController => JrcFlows::NativeResponderHooks::ConversationActor
  }.each do |target, hook|
    target.prepend(hook) unless target.ancestors.include?(hook)
    next unless target.name.start_with?('Api::')

    target.rescue_from(JrcFlows::OwnershipGuard::Closed, JrcFlows::OwnershipEffects::Duplicate) do
      render json: { code: 'FLOW_NATIVE_INBOX_FENCED' }, status: :forbidden
    end
  end
end
