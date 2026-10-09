class JrcRelationship::PlaybookFlowJournal
  PURPOSE = 'relationship-playbook-effects'.freeze

  def initialize(run)
    @run = run
  end

  def effect
    records = verify_integrity!
    previous = records[@run.node_id]
    return native_message!(previous) if previous

    message = yield
    raise ArgumentError, 'playbook_flow_native_message_required' unless message.is_a?(Message) && message.persisted?

    record = { 'message_id' => message.id, 'message_digest' => message_digest(message) }
    record['attachment_digest'] = attachment_digest(message) if message.attachments.exists?
    records = records.merge(@run.node_id => record)
    journal = { 'records' => records, 'signature' => verifier.generate(binding(records), purpose: PURPOSE) }
    @run.update!(settings: @run.settings.merge(JrcRelationship::PlaybookFlowContinuation::JOURNAL_KEY => journal))
    message
  end

  def verify_integrity!
    journal = @run.settings[JrcRelationship::PlaybookFlowContinuation::JOURNAL_KEY]
    return {} unless journal

    records = journal.fetch('records')
    raise ArgumentError, 'playbook_flow_effect_journal_changed' unless records.is_a?(Hash) &&
                                                                       verifier.verified(journal.fetch('signature'),
                                                                                         purpose: PURPOSE) == binding(records)

    records.each_value { |record| native_message!(record) }
    records
  end

  def verify_outcomes!
    verify_integrity!.each_value do |record|
      state = native_message!(record).content_attributes['jrc_flow_delivery']
      raise ArgumentError, 'playbook_flow_external_outcome_unconfirmed' if %w[unknown dispatching].include?(state)
    end
  end

  private

  def native_message!(record)
    message = Message.where(account_id: @run.account_id, conversation_id: @run.conversation_id).find(record.fetch('message_id'))
    raise ArgumentError, 'playbook_flow_effect_resource_changed' unless message.content_attributes['jrc_flow_run_id'] == @run.id
    raise ArgumentError, 'playbook_flow_message_payload_changed' unless record.fetch('message_digest') == message_digest(message)
    if record.key?('attachment_digest') && record['attachment_digest'] != attachment_digest(message)
      raise ArgumentError, 'playbook_flow_media_payload_changed'
    end

    message
  end

  def attachment_digest(message)
    rows = message.attachments.order(:id).map do |attachment|
      blob = attachment.file.blob
      { 'attachment' => attachment.attributes.slice('id', 'account_id', 'message_id', 'file_type'),
        'blob' => blob.attributes.slice('id', 'key', 'filename', 'content_type', 'byte_size', 'checksum') }
    end
    JrcRelationship::PlaybookFlowReference.digest(rows)
  end

  def message_digest(message)
    JrcRelationship::PlaybookFlowReference.digest(
      'message' => message.attributes.slice('id', 'account_id', 'conversation_id', 'content', 'private', 'message_type', 'content_type'),
      'origin' => message.content_attributes.to_h.slice('jrc_flow_run_id', 'jrc_flow_node_id'), 'attachment_ids' => message.attachments.ids.sort
    )
  end

  def binding(records)
    { 'run_id' => @run.id, 'event_key' => @run.event_key, 'records' => records }
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
