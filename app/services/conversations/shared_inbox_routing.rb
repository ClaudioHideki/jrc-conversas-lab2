# A request-local proof of no routing, never a persisted sharing preference.
class Conversations::SharedInboxRouting
  def initialize(account:, user:, inbox_ids:)
    @account = account
    @user = user
    @inbox_ids = account.inboxes.where(id: inbox_ids).pluck(:id)
  end

  def perform
    return [] if @inbox_ids.empty?

    blocked = local_blockers
    bindings = JrcBrokerInboxBinding.where(account_id: @account.id, inbox_id: @inbox_ids).to_a
    # Local revocation can leave a live remote bot; every retained binding still needs remote proof.
    native = JrcFlowNativeBinding.where(account_id: @account.id, inbox_id: @inbox_ids).to_a
    # Conflicting native tuples are never treated as absent.
    conflicting = native.select { |row| bindings.any? { |binding| binding.inbox_id == row.inbox_id && binding.integration_id != row.integration_id } }
    blocked |= conflicting.map(&:inbox_id)
    targets = bindings + native
    proof = targets.empty? ? {} : JrcBroker::RoutingContext.new(account: @account, user: @user, bindings: targets).perform
    targets.each { |binding| blocked << binding.inbox_id unless proof[binding.inbox_id] == 'NONE' }
    ApplicationRecord.uncached do
      blocked |= local_blockers # Local routing may have changed while HTTP was in flight.
      fresh = JrcBrokerInboxBinding.where(account_id: @account.id, inbox_id: @inbox_ids).to_a +
              JrcFlowNativeBinding.where(account_id: @account.id, inbox_id: @inbox_ids).to_a
      previous = targets.map { |binding| target_tuple(binding) }
      current = fresh.map { |binding| target_tuple(binding) }
      blocked |= ((previous - current) | (current - previous)).map(&:first)
    end
    @inbox_ids - blocked
  end

  private

  def target_tuple(binding)
    %i[inbox_id integration_id instance_id channel_id registration_id registration_revision].map do |field|
      binding.public_send(field) if binding.respond_to?(field)
    end
  end

  def local_blockers
    native_bot_inboxes | configured_flow_inboxes | live_flow_inboxes | ownership_inboxes
  end

  def native_bot_inboxes
    ids = AgentBotInbox.where(inbox_id: @inbox_ids, status: :active).pluck(:inbox_id)
    ids |= Integrations::Hook.where(account_id: @account.id, inbox_id: @inbox_ids, app_id: 'dialogflow', status: :enabled).pluck(:inbox_id)
    ids |= CaptainInbox.where(inbox_id: @inbox_ids).pluck(:inbox_id) if ChatwootApp.enterprise?
    ids
  end

  def configured_flow_inboxes
    JrcFlow.where(account_id: @account.id, connection_id: nil, status: 'active').pluck(:settings)
           .flat_map { |settings| Array(settings['inbox_ids']).map(&:to_i) } & @inbox_ids
  end

  def live_flow_inboxes
    JrcFlowRun.live.where(account_id: @account.id).joins(:conversation)
              .where(conversations: { account_id: @account.id, inbox_id: @inbox_ids }).distinct.pluck('conversations.inbox_id')
  end

  def ownership_inboxes
    JrcFlowOwnershipScope.joins('INNER JOIN jrc_flow_ownership_executions e ON e.scope_key = jrc_flow_ownership_scopes.scope_key ' \
                               'AND e.generation = jrc_flow_ownership_scopes.generation')
                        .where(account_id: @account.id, inbox_id: @inbox_ids, host_origin: ENV.fetch('FRONTEND_URL', '').delete_suffix('/'))
                        .where(e: { state: %w[RUNNING UNKNOWN] }).distinct.pluck(:inbox_id)
  end
end
