# frozen_string_literal: true

# A finite outbox for one existing native webhook node. Intent and receipts are
# signed inside the native Run JSON; this class never dispatches a request.
class JrcRelationship::PlaybookFlowWebhookJournal
  KEY = '_relationship_webhooks'
  PURPOSE = 'relationship-playbook-webhooks'
  STATES = %w[queued dispatching response_received unknown cancelled].freeze
  PENDING = :relationship_webhook_pending

  def initialize(run)
    @run = run
  end

  def enqueue!(data)
    records = verify_integrity!
    previous = records[@run.node_id]
    return PENDING if previous && %w[queued dispatching].include?(previous.fetch('state'))
    raise ArgumentError, 'playbook_flow_webhook_already_consumed' if previous

    payload = { 'event' => 'jrc.flow', 'flow_id' => @run.flow_id, 'run_id' => @run.id,
                'conversation_id' => @run.conversation.display_id,
                'data' => JrcFlows::Evaluator.new(@run.variables).render(data['body']) }
    record = { 'state' => 'queued', 'data_digest' => digest(data), 'payload' => payload,
               'payload_digest' => digest(payload), 'queued_at' => Time.current.iso8601(6),
               'incoming_watermark' => @run.conversation.messages.incoming.maximum(:id).to_i }
    persist!(records.merge(@run.node_id => record), status: 'waiting', wake_at: nil)
    PENDING
  end

  def verify_integrity!
    journal = @run.settings[KEY]
    return {} unless journal

    records = journal.fetch('records')
    valid = records.is_a?(Hash) && records.size.between?(1, 150) &&
            verifier.verified(journal.fetch('signature'), purpose: PURPOSE) == binding(records)
    raise ArgumentError, 'playbook_flow_webhook_journal_changed' unless valid

    records.each { |node_id, record| validate_record!(node_id, record) }
    records
  end

  def verify_outcomes!
    if verify_integrity!.values.any? { |record| %w[dispatching unknown cancelled].include?(record.fetch('state')) }
      raise ArgumentError, 'playbook_flow_webhook_outcome_unconfirmed'
    end
  end

  def pending?
    record = verify_integrity![@run.node_id]
    record && %w[queued dispatching].include?(record.fetch('state'))
  end

  def update!(node_id, **attributes)
    records = verify_integrity!
    record = records.fetch(node_id).merge(attributes.stringify_keys)
    validate_record!(node_id, record)
    persist!(records.merge(node_id => record))
    record
  end

  private

  def validate_record!(node_id, record)
    node = @run.graph.fetch('nodes').find { |item| item['id'] == node_id }
    valid = node && node['type'] == 'webhook' && record.is_a?(Hash) && STATES.include?(record['state']) &&
            record['data_digest'] == digest(node.fetch('data')) && record['payload_digest'] == digest(record.fetch('payload'))
    raise ArgumentError, 'playbook_flow_webhook_payload_changed' unless valid
  end

  def persist!(records, **attributes)
    journal = { 'records' => records, 'signature' => verifier.generate(binding(records), purpose: PURPOSE) }
    @run.update!(settings: @run.settings.merge(KEY => journal), **attributes)
  end

  def binding(records)
    { 'run_id' => @run.id, 'account_id' => @run.account_id, 'flow_id' => @run.flow_id, 'event_key' => @run.event_key,
      'stamp' => @run.settings.fetch(JrcRelationship::PlaybookFlow::STAMP_KEY), 'records' => records }
  end

  def digest(value)
    JrcRelationship::PlaybookFlowReference.digest(value)
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
