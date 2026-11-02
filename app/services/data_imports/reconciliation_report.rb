# Local diagnostics only: no source request, import, retry, approval or NICO gate.
class DataImports::ReconciliationReport
  TARGETS = { 'contact' => Contact, 'conversation' => Conversation, 'message' => Message }.freeze

  def initialize(data_import:)
    @import = data_import
    @account_id = data_import.account_id
    @provider = data_import.source_provider
  end

  def call
    entities = entity_types.map { |type| entity_report(type) }
    integrity = integrity_counts
    logs = log_counts
    attachments = attachment_coverage
    {
      data_import_id: @import.id, source_provider: @provider, generated_at: Time.current.iso8601,
      source_checked: false, acceptance: 'not_reviewed', totals_basis: 'stored_import_stats',
      status: report_status(entities, integrity, logs, attachments),
      entities: entities, integrity: integrity, logs: logs, attachments: attachments
    }
  end

  private

  def entity_types
    types = Array(@import.import_types).presence || (@import.intercom_import? ? %w[contacts conversations] : ['contacts'])
    result = []
    result << 'contact' if types.include?('contacts')
    result.push('conversation', 'message') if types.include?('conversations')
    result
  end

  def entity_report(type)
    items = @import.items.where(source_object_type: type, source_provider: @provider).group(:status).count
    counts = %w[pending processing imported skipped failed].index_with { |status| items.fetch(status, 0) }
    mappings = mapping_counts(type)
    total = @import.stats.to_h.dig("#{type}s", 'total')
    total = nil unless total.is_a?(Integer) && total >= 0
    difference = total.nil? ? nil : total - mappings[:valid]
    {
      type: type, source_total: total, items: counts, mappings: mappings, difference: difference,
      comparison: comparison_for(difference)
    }
  end

  def comparison_for(difference)
    return 'unknown' if difference.nil?

    difference.zero? ? 'equal' : 'different'
  end

  # A reused mapping may belong to an older import. Follow immutable source keys
  # observed by this run, not just mappings whose latest data_import_id is ours.
  def mappings_for(type)
    current = DataImportMapping.where(id: @import.mappings.where(source_object_type: type).select(:id))
    shared = DataImportMapping.where(account_id: @account_id, source_provider: @provider, source_object_type: type)
    items = @import.items.where(source_provider: @provider, source_object_type: type).select(:source_object_id)
    errors = @import.import_errors.where(source_object_type: type).select(:source_object_id)
    current.or(shared.where(source_object_id: items)).or(shared.where(source_object_id: errors))
  end

  def mapping_counts(type)
    mappings = mappings_for(type)
    owned = mappings.where(account_id: @account_id, source_provider: @provider)
    model = TARGETS.fetch(type)
    native = owned.where(chatwoot_record_type: model.name)
    skipped = skipped_mappings(type, owned)
    counts = combined_target_counts(native, skipped, model)
    counts.merge(total: mappings.count, skipped: skipped.count, unmapped_items: unmapped_item_count(type, owned),
                 unsupported: unsupported_mapping_count(owned, native, skipped))
  end

  def skipped_mappings(type, owned)
    return owned.none unless type == 'message'

    owned.where(chatwoot_record_type: 'Conversation').where("metadata ->> 'skipped' = ?", 'true')
  end

  def combined_target_counts(native, skipped, model)
    counts = target_counts(native, model)
    skip_targets = target_counts(skipped, Conversation)
    counts.merge(missing: counts[:missing] + skip_targets[:missing], cross_account: counts[:cross_account] + skip_targets[:cross_account])
  end

  def unmapped_item_count(type, owned)
    processed = @import.items.where(source_provider: @provider, source_object_type: type, status: %i[imported skipped])
    processed.where.not(source_object_id: owned.select(:source_object_id)).count
  end

  def unsupported_mapping_count(owned, native, skipped)
    owned.where.not(id: native.select(:id)).where.not(id: skipped.select(:id)).count
  end

  def target_counts(mappings, model)
    {
      valid: mappings.where(chatwoot_record_id: model.where(account_id: @account_id).select(:id)).count,
      missing: mappings.where.not(chatwoot_record_id: model.select(:id)).count,
      cross_account: mappings.where(chatwoot_record_id: model.where.not(account_id: @account_id).select(:id)).count
    }
  end

  def integrity_counts
    mapping_integrity_counts.merge(item_integrity_counts)
  end

  def mapping_integrity_counts
    mappings = @import.mappings
    {
      foreign_account_mappings: mappings.where.not(account_id: @account_id).count,
      unexpected_provider_mappings: mappings.where.not(source_provider: @provider).count,
      unsupported_source_types: mappings.where.not(source_object_type: TARGETS.keys).count,
      unselected_mapping_types: mappings.where.not(source_object_type: entity_types).count
    }
  end

  def item_integrity_counts
    items = @import.items
    {
      unexpected_item_sources: items.where.not(source_provider: @provider).count,
      unselected_item_types: items.where.not(source_object_type: entity_types).count,
      unsupported_item_types: items.where.not(source_object_type: TARGETS.keys).count
    }
  end

  def log_counts
    {
      errors: @import.import_errors.non_skip_logs.count,
      failed: @import.import_errors.failed.count,
      skipped: @import.import_errors.where("details ->> 'kind' = ?", 'skipped').count
    }
  end

  def attachment_coverage
    applicable = entity_types.include?('message')
    referenced = if applicable
                   mappings_for('message').where(account_id: @account_id, source_provider: @provider)
                                          .where("jsonb_typeof(metadata #> '{source,attachments}') = 'array'")
                                          .where("metadata #> '{source,attachments}' <> '[]'::jsonb").count
                 else
                   0
                 end
    { coverage: applicable ? 'not_supported' : 'not_applicable', integrity_verified: false, referenced_messages: referenced }
  end

  def report_status(entities, integrity, logs, attachments)
    return 'differences_found' if integrity.values.any?(&:positive?) || differing_entities?(entities)
    return 'incomplete' if incomplete_entities?(entities) || incomplete_evidence?(logs, attachments)

    'local_checks_passed'
  end

  def differing_entities?(entities)
    entities.any? do |entity|
      invalid = entity[:mappings].values_at(:missing, :cross_account, :unsupported, :unmapped_items).any?(&:positive?)
      invalid || entity[:comparison] == 'different'
    end
  end

  def incomplete_entities?(entities)
    entities.empty? || entities.any? do |entity|
      pending = entity[:items].values_at('pending', 'processing', 'failed').any?(&:positive?)
      entity[:source_total].nil? || pending || entity[:mappings][:skipped].positive?
    end
  end

  def incomplete_evidence?(logs, attachments)
    !@import.intercom_import? || !@import.completed? || logs.values.any?(&:positive?) || attachments[:coverage] == 'not_supported'
  end
end
