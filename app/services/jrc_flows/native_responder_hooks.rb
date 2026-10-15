module JrcFlows::NativeResponderHooks
  module Rules
    %i[send_message send_attachment assign_agent assign_team remove_assigned_agent remove_assigned_team change_status
       resolve_conversation open_conversation pending_conversation snooze_conversation mute_conversation].each do |action|
      define_method(action) do |params|
        @native_action_sequence = @native_action_sequence.to_i + 1
        incoming = @conversation.messages.incoming.maximum(:id).to_i
        reference = "native-rule:#{@rule.id}:#{@conversation.id}:#{incoming}:#{action}:#{@native_action_sequence}"
        kind = %i[send_message send_attachment].include?(action) ? 'MESSAGE' : 'DATABASE'
        JrcFlows::NativeResponders.perform(inbox: @conversation.inbox, path: 'automation-rule', reference: reference, kind: kind) { super(params) }
      rescue JrcFlows::OwnershipGuard::Closed, JrcFlows::OwnershipEffects::Duplicate
        nil
      end
      private action
    end

    private

    def send_webhook_event(urls)
      return unless JrcFlows::OwnershipGuard.allowed_local?(@conversation.account_id, @conversation.inbox_id)

      payload = @conversation.webhook_data.merge(event: "automation_event.#{@rule.event_name}")
      JrcFlows::NativeResponderWebhookJob.perform_later(@conversation.account_id, @conversation.inbox_id, SecureRandom.uuid, urls[0], payload)
    end
  end

  module Replies
    def perform(message_id)
      message = Message.find(message_id)
      JrcFlows::NativeResponders.delivery(message) { super }
    end
  end

  module MessageWebhooks
    def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil)
      body = payload.is_a?(Hash) ? payload.with_indifferent_access : {}
      message = if %w[message_created message_updated].include?(body['event'])
                  Message.find_by(id: body['id'], account_id: body.dig('account', 'id') || body['account_id'])
                end
      return super unless message

      reference = "native-message-webhook:#{message.id}:#{delivery_id || job_id}"
      JrcFlows::NativeResponders.delivery(message, reference: reference) { super }
    end
  end

  module BotListener
    private

    def agent_bots_for(inbox, conversation = nil)
      super.select do |bot|
        JrcFlows::OwnershipGuard.allowed_local?(inbox.account_id, inbox.id) || JrcFlows::NativeResponders.broker_bot?(inbox, bot)
      end
    end
  end

  module BotWebhook
    def perform(url, payload, webhook_type = :agent_bot_webhook, secret: nil, delivery_id: nil,
                native_account_id: nil, native_inbox_id: nil, native_bot_id: nil, native_epoch_id: nil)
      inbox = Inbox.find_by(id: native_inbox_id, account_id: native_account_id)
      bot = AgentBot.find_by(id: native_bot_id)
      raise JrcFlows::OwnershipGuard::Closed, 'FLOW_NATIVE_JOB_PROVENANCE_REQUIRED' unless inbox && bot && delivery_id &&
                                                                                           bot.outgoing_url == url && bot.secret == secret

      scope = JrcFlows::NativeResponders.scope_for(inbox)
      if (scope&.state == 'FENCED') && !(native_epoch_id && native_epoch_id == scope.current_epoch_id)
        raise JrcFlows::OwnershipGuard::Closed, 'FLOW_NATIVE_JOB_EPOCH_CHANGED'
      end

      JrcFlows::NativeResponders.perform(inbox: inbox, path: 'agent-bot-webhook', reference: "native-bot:#{delivery_id}", kind: 'EXTERNAL',
                                         bot: bot) do
        super(url, payload, webhook_type, secret: secret, delivery_id: delivery_id)
      end
    end
  end

  module MessageActor
    def create
      JrcFlows::NativeResponders.api_actor(@conversation.inbox, Current.user || @resource, reference: "native-api-message:#{SecureRandom.uuid}",
                                                                                           kind: 'MESSAGE') do
        super
      end
    end
  end

  module AssignmentActor
    def create
      JrcFlows::NativeResponders.api_actor(@conversation.inbox, Current.user || @resource, reference: "native-api-assignment:#{SecureRandom.uuid}") do
        super
      end
    end
  end

  module ConversationActor
    def create
      kind = params[:message].present? ? 'MESSAGE' : 'DATABASE'
      JrcFlows::NativeResponders.api_actor(@inbox, Current.user || @resource, reference: "native-api-conversation:#{SecureRandom.uuid}",
                                                                              kind: kind) do
        super
      end
    end

    def toggle_status
      JrcFlows::NativeResponders.api_actor(@conversation.inbox, Current.user || @resource, reference: "native-api-status:#{SecureRandom.uuid}") do
        super
      end
    end

    def update
      JrcFlows::NativeResponders.api_actor(@conversation.inbox, Current.user || @resource, reference: "native-api-update:#{SecureRandom.uuid}") do
        super
      end
    end
  end
end
