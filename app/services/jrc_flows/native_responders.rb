require 'digest'

# Admission for the existing native executors. The callback exception is a
# server-authenticated registration/epoch binding, never a URL allowlist.
class JrcFlows::NativeResponders
  TRIGGERS = {
    'jrc_native_agent_bot_inbox_fence' => 'agent_bot_inboxes',
    'jrc_native_agent_bot_fence' => 'agent_bots',
    'jrc_native_conversation_bot_fence' => 'conversations',
    'jrc_native_inbox_policy_fence' => 'inboxes'
  }.freeze

  def self.installed!
    db = ApplicationRecord.connection
    found = db.select_rows(<<~SQL).to_h
      SELECT t.tgname,c.relname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
      WHERE t.tgname IN (#{TRIGGERS.keys.map { |name| db.quote(name) }.join(',')}) AND t.tgenabled='O' AND NOT t.tgisinternal
        AND t.tgfoid='jrc_native_responder_config_fence()'::regprocedure
    SQL
    raise JrcFlows::OwnershipGuard::Closed, 'FLOW_NATIVE_POLICY_NOT_INSTALLED' unless found == TRIGGERS

    sql = File.read(Rails.root.join('db/functions/20261015160000_native_responder_config_fence.sql'))
    expected = sql.split('$JRC_NATIVE_FENCE$').fetch(1)
    actual = db.select_value("SELECT prosrc FROM pg_proc WHERE oid='jrc_native_responder_config_fence()'::regprocedure")
    unless Digest::SHA256.hexdigest(actual.to_s) == Digest::SHA256.hexdigest(expected)
      raise JrcFlows::OwnershipGuard::Closed,
            'FLOW_NATIVE_POLICY_CHANGED'
    end

    true
  end

  def self.scope_for(inbox)
    JrcFlowOwnershipScope.find_by(scope_key: JrcFlows::OwnershipGuard.key(JrcFlows::OwnershipGuard.local_origin, inbox.account_id, inbox.id))
  end

  def self.verify_pair!(inbox, bot_id, callback)
    valid = (bot_id.nil? && callback.nil?) || (bot_id.is_a?(Integer) && bot_id.positive? && callback.is_a?(String) && callback.present?)
    raise JrcFlows::NativeOwnership::Denied unless valid

    link = AgentBotInbox.find_by(inbox_id: inbox.id, status: AgentBotInbox.statuses.fetch('active'))
    bot = link&.agent_bot
    raise JrcFlows::NativeOwnership::Denied unless bot&.id == bot_id && bot&.outgoing_url == callback

    assigned = inbox.conversations.where.not(assignee_agent_bot_id: nil)
    assigned = assigned.where.not(assignee_agent_bot_id: bot_id) if bot_id
    raise JrcFlows::NativeOwnership::Denied if assigned.exists?
    raise JrcFlows::NativeOwnership::Denied if inbox.greeting_enabled? || inbox.enable_auto_assignment?

    true
  end

  def self.broker_epoch!(scope, bot)
    epoch = JrcFlowOwnershipEpoch.find_by(id: scope.current_epoch_id, scope_id: scope.id, state: %w[FENCED DRAINED])
    record = epoch&.registration
    now = ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    valid = scope.state == 'FENCED' && epoch && record && record.state == 'ACTIVE' && record.revoked_at.nil? && record.callback_digest.present? &&
            record.revision == epoch.registration_revision && record.expires_at > now && record.credential_expires_at > now &&
            epoch.broker_agent_bot_id == bot.id && epoch.broker_agent_bot_callback == bot.outgoing_url &&
            record.account_id == scope.account_id && record.bindings.exists?(inbox_id: scope.inbox_id, integration_id: epoch.integration_id,
                                                                             channel_id: epoch.channel_id, registration_revision: record.revision)
    raise JrcFlows::OwnershipGuard::Closed, 'FLOW_BROKER_BOT_BINDING_CHANGED' unless valid

    verify_pair!(Inbox.find(scope.inbox_id), bot.id, bot.outgoing_url)
    epoch
  end

  def self.broker_bot?(inbox, bot)
    scope = scope_for(inbox)
    return false unless scope&.state == 'FENCED'

    broker_epoch!(scope, bot)
    true
  rescue JrcFlows::OwnershipGuard::Closed, JrcFlows::NativeOwnership::Denied
    false
  end

  def self.perform(inbox:, path:, reference:, kind:, bot: nil)
    canonical = bot && broker_bot?(inbox, bot) ? bot : nil
    JrcFlows::OwnershipGuard.with_local(inbox.account_id, inbox.id, path: path, reference: reference, broker_bot: canonical) do
      operation = lambda do
        JrcFlows::OwnershipEffects.perform(reference: reference, kind: kind) do
          result = yield
          if kind == 'MESSAGE' && result.is_a?(Message) && result.outgoing? && !result.private?
            result.update!(content_attributes: result.content_attributes.to_h.merge('jrc_native_delivery' => 'queued'))
          end
          result
        end
      end
      if kind == 'EXTERNAL'
        raise JrcFlows::OwnershipGuard::Closed, 'FLOW_NATIVE_HTTP_IN_TRANSACTION' if ApplicationRecord.connection.transaction_open?

        operation.call
      else
        ApplicationRecord.transaction { operation.call }
      end
    end
  end

  def self.api_actor(inbox, actor, reference:, kind: 'DATABASE', &)
    return yield unless actor.is_a?(AgentBot)

    perform(inbox: inbox, path: 'api-bot-actor', reference: reference, kind: kind, bot: actor, &)
  end

  def self.delivery(message, reference: "native-reply:#{message.id}", &)
    effect = JrcFlowOwnershipEffect.where(message_id: message.id, kind: 'MESSAGE').order(:created_at).last
    execution = effect && JrcFlowOwnershipExecution.find_by(id: effect.execution_id)
    if execution&.authority_kind == 'BROKER_CALLBACK'
      scope = scope_for(message.inbox)
      raise JrcFlows::OwnershipGuard::Closed unless scope && scope.current_epoch_id == execution.authority_epoch_id
    end
    bot = execution&.authority_kind == 'BROKER_CALLBACK' ? AgentBot.find_by(id: execution.authority_bot_id) : nil
    # A sender ID supplied in params is never a callback admission receipt.
    return yield unless effect || message.sender_type == 'AgentBot'

    perform(inbox: message.inbox, path: 'native-reply', reference: reference, kind: 'EXTERNAL', bot: bot, &)
    JrcFlows::OwnershipEffects.refresh_message!(message.id)
  rescue JrcFlows::OwnershipGuard::Closed, JrcFlows::OwnershipEffects::Duplicate
    if effect && %w[OBSERVED QUEUED].include?(effect.reload.state) && !external_uncertainty?(effect)
      message.update!(status: :failed, content_attributes: message.content_attributes.to_h.merge('jrc_native_delivery' => 'cancelled'))
      JrcFlowOwnershipEffect.where(message_id: message.id, kind: 'MESSAGE', state: %w[OBSERVED QUEUED]).update_all(state: 'CANCELED')
    end
    nil
  end

  def self.legacy_message?(message)
    effect = JrcFlowOwnershipEffect.where(message_id: message.id, kind: 'MESSAGE').order(:created_at).last
    execution = effect && JrcFlowOwnershipExecution.find_by(id: effect.execution_id)
    return execution.authority_kind == 'LEGACY' if execution

    message.sender_type == 'AgentBot'
  end

  def self.drain_executions(scope)
    JrcFlowOwnershipExecution.where(scope_key: scope.scope_key)
                             .where("NOT (authority_kind='BROKER_CALLBACK' AND entrypoint='agent-bot-webhook')")
  end

  def self.external_uncertainty?(effect)
    JrcFlowOwnershipEffect.where(scope_key: effect.scope_key, kind: 'EXTERNAL', state: %w[DISPATCHED OBSERVED UNKNOWN]).exists?
  end

  def self.quiesce_messages!(scope)
    Message.where(account_id: scope.account_id, inbox_id: scope.inbox_id, private: false).find_each do |message|
      next unless legacy_message?(message)

      effect = JrcFlowOwnershipEffect.where(message_id: message.id, kind: 'MESSAGE').order(:created_at).last
      unless effect
        unless %w[delivered read].include?(message.status)
          JrcFlows::NativeOwnership.new.retain_legacy_unknown!(scope, "native-unproven-message:#{message.id}")
        end
        next
      end
      JrcFlows::OwnershipEffects.refresh_message!(message.id)
      next unless %w[OBSERVED QUEUED].include?(effect.reload.state)
      next if external_uncertainty?(effect)

      message.update!(status: :failed, content_attributes: message.content_attributes.to_h.merge('jrc_native_delivery' => 'cancelled'))
      JrcFlowOwnershipEffect.where(id: effect.id, state: %w[OBSERVED QUEUED]).update_all(state: 'CANCELED')
    end
  end
end
