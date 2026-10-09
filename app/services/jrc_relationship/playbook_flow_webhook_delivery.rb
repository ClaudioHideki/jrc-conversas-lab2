# frozen_string_literal: true

# Transport for a reviewed native webhook intent. The dispatch claim commits
# before SafeFetch POST. Unknown outcomes are terminal and never reposted.
class JrcRelationship::PlaybookFlowWebhookDelivery
  def initialize(run, node_id)
    @run = run
    @node_id = node_id
    @journal = JrcRelationship::PlaybookFlowWebhookJournal.new(run)
  end

  def perform
    return unless JrcRelationship::PlaybookFlowContinuation.managed?(@run)
    raise ArgumentError, 'playbook_flow_webhook_requires_committed_intent' if JrcFlowRun.connection.transaction_open?

    claimed = with_current_sources { claim! }
    return unless claimed

    completed = with_current_sources { dispatch! }
    JrcFlows::Runner.new(@run.reload).perform if completed
  rescue JrcRelationship::PlaybookFlowSourceDenied, Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError, KeyError
    halt!(claimed ? 'unknown' : 'cancelled')
  rescue StandardError => error
    Rails.logger.warn("JRC Flow webhook run=#{@run.id} node=#{@node_id} failed: #{error.class}")
    halt!('unknown')
  end

  def self.recover(run)
    journal = JrcRelationship::PlaybookFlowWebhookJournal.new(run)
    journal.verify_integrity!.each do |node_id, record|
      if record['state'] == 'queued'
        JrcRelationship::PlaybookFlowWebhookJob.perform_later(run.id, node_id)
      elsif record['state'] == 'dispatching' && Time.iso8601(record.fetch('claimed_at')) < 2.minutes.ago
        new(run, node_id).send(:halt!, 'unknown')
      end
    end
  rescue ArgumentError, KeyError
    run.update!(status: 'paused', error: 'playbook_flow_webhook_authorization_blocked', wake_at: nil)
  end

  private

  def with_current_sources
    JrcRelationship::PlaybookFlowContinuation.with_sources(@run) do
      @run.lock!
      @run.conversation.lock!
      context = JrcRelationship::PlaybookFlowRunContext.new(@run).authorize!
      node = @run.graph.fetch('nodes').find { |item| item['id'] == @node_id }
      raise ArgumentError, 'playbook_flow_webhook_node_changed' unless node && node['type'] == 'webhook'

      authorize_started_node!(context, node)
      JrcRelationship::PlaybookFlowJournal.new(@run).verify_outcomes!
      authorize_owner!
      yield
    end
  end

  def authorize_started_node!(context, node)
    # The existing Runner already charged this node when it committed the
    # signed intent. Transport cannot grant an additional graph step.
    raise ArgumentError, 'playbook_flow_step_limit' if @run.steps > context.reference.policy.definition.fetch('max_steps')
    raise ArgumentError, 'playbook_flow_node_payload_changed' unless context.reference.flow.graph.fetch('nodes').include?(node)

    JrcRelationship::PlaybookFlowDeliveryGuard.new(context.reference).authorize!('webhook', node.fetch('data'))
  end

  def authorize_owner!
    conversation = @run.conversation
    record = @journal.verify_integrity!.fetch(@node_id)
    owned = conversation.assignee_agent_bot_id || JrcFlows::Access.inbox_bot_owned?(conversation) ||
            (@run.settings.fetch('pause_on_agent', true) && conversation.assignee_id) ||
            (@run.settings.fetch('pause_on_team', false) && conversation.team_id)
    changed = conversation.messages.outgoing.where(sender_type: 'User', private: false).where('created_at > ?', @run.created_at).exists? ||
              conversation.messages.incoming.where('id > ?', record.fetch('incoming_watermark')).exists?
    raise Pundit::NotAuthorizedError if owned || changed
  end

  def claim!
    record = @journal.verify_integrity![@node_id]
    return false unless record && record['state'] == 'queued' && @run.status == 'waiting' && @run.node_id == @node_id

    @claim = SecureRandom.uuid
    @journal.update!(@node_id, state: 'dispatching', claim: @claim, claimed_at: Time.current.iso8601(6))
    true
  end

  def dispatch!
    record = @journal.verify_integrity!.fetch(@node_id)
    return false unless record['state'] == 'dispatching' && record['claim'] == @claim && @run.status == 'waiting' && @run.node_id == @node_id

    node = @run.graph.fetch('nodes').find { |item| item['id'] == @node_id }
    response = fetch_response(node.fetch('data').fetch('url'), record.fetch('payload'))
    @journal.update!(@node_id, state: 'response_received', response_digest: Digest::SHA256.hexdigest(response),
                              completed_at: Time.current.iso8601(6))
    @run.variables['webhook_response'] = response
    edge = @run.graph.fetch('edges').find { |item| item['source'] == @node_id && item['port'] == 'next' }
    raise ArgumentError, 'playbook_flow_webhook_edge_missing' unless edge

    @run.update!(node_id: edge.fetch('target'), status: 'running', wake_at: nil, variables: @run.variables)
    true
  end

  def fetch_response(url, payload)
    response = nil
    SafeFetch.fetch(url, method: :post, body: payload.to_json, max_bytes: 100_000, validate_content_type: false, read_timeout: 10,
                        headers: { 'Content-Type' => 'application/json', 'Idempotency-Key' => "jrc-flow-#{@run.id}-#{@node_id}" }) do |result|
      response = result.tempfile.read.first(10_000)
    end
    response
  end

  def halt!(state)
    @run.with_lock do
      record = @journal.verify_integrity![@node_id]
      return unless record && %w[queued dispatching].include?(record['state'])
      return if record['state'] == 'dispatching' && @claim && record['claim'] != @claim

      @journal.update!(@node_id, state: state, completed_at: Time.current.iso8601(6))
      @run.update!(status: 'paused', wake_at: nil, finished_at: Time.current, error: 'playbook_flow_webhook_outcome_unconfirmed')
    end
  rescue ActiveRecord::RecordNotFound, ArgumentError, KeyError
    @run.reload.update!(status: 'paused', wake_at: nil, error: 'playbook_flow_webhook_authorization_blocked') if @run.persisted?
  end
end
