# frozen_string_literal: true

# Proof of native mutations belonging to this reviewed run. It does not grant
# effects, alter actor permissions, or execute a second Flow engine.
class JrcRelationship::PlaybookFlowMutationJournal
  KEY = '_relationship_mutations'
  PURPOSE = 'relationship-playbook-mutations'
  VARIABLE_KEYS = %w[lead_id activity_id deal_id delegation_id contact.name contact.email contact.phone_number].freeze

  def initialize(run)
    @run = run
    @state = JrcRelationship::PlaybookFlowMutationState.new(run)
  end

  def normalize_reference!(reference)
    journal = verified!(reference)
    reference.normalize_owned_mutations!(journal.fetch('baseline')) if journal
    reference
  end

  def effect(reference:, type:, data:)
    journal = verified!(reference)
    records = journal ? journal.fetch('records') : []
    previous = records.find { |record| record['node_id'] == @run.node_id }
    return replay!(previous, type, data) if previous

    before = @state.call(prior_resources(records))
    target_before = @state.target_before(type, data)
    yield
    record = mutation_record(type, data, before).merge('target_before' => target_before).compact
    baseline = journal ? journal.fetch('baseline') : before
    persist!(reference, baseline, records + [record])
    nil
  end

  def verified!(reference)
    journal = @run.settings[KEY]
    return unless journal
    raise ArgumentError, 'playbook_flow_mutation_journal_changed' unless journal.is_a?(Hash)

    records = journal.fetch('records')
    valid = records.is_a?(Array) && records.size.between?(1, 150) &&
            verifier.verified(journal.fetch('signature'), purpose: PURPOSE) == binding(reference, journal.except('signature'))
    raise ArgumentError, 'playbook_flow_mutation_journal_changed' unless valid

    verify_chain!(journal)
    latest = records.last.fetch('after')
    raise ArgumentError, 'playbook_flow_native_mutation_changed' unless @state.call(latest.fetch('resources')) == latest

    journal
  end

  private

  def prior_resources(records)
    records.last&.dig('after', 'resources') || []
  end

  def mutation_record(type, data, before)
    resources = before.fetch('resources') + @state.variable_resources(type)
    after = @state.call(resources.uniq { |resource| resource.values_at('kind', 'id') })
    { 'node_id' => @run.node_id, 'type' => type, 'data_digest' => digest(data), 'before' => before, 'after' => after,
      'variables' => @run.variables.slice(*VARIABLE_KEYS) }
  end

  def verify_chain!(journal)
    previous = journal.fetch('baseline')
    nodes = []
    journal.fetch('records').each do |record|
      node = @run.graph.fetch('nodes').find { |item| item['id'] == record.fetch('node_id') }
      raise ArgumentError, 'playbook_flow_mutation_chain_changed' unless valid_record?(record, node, previous, nodes)

      previous = record.fetch('after')
      nodes << node['id']
    end
  end

  def valid_record?(record, node, previous, nodes)
    node && node['type'] == record.fetch('type') && digest(node.fetch('data')) == record.fetch('data_digest') &&
      record.fetch('before') == previous && nodes.exclude?(node['id'])
  end

  def replay!(record, type, data)
    valid = record.values_at('type', 'data_digest') == [type, digest(data)]
    raise ArgumentError, 'playbook_flow_mutation_payload_changed' unless valid

    @run.variables.merge!(record.fetch('variables'))
    nil
  end

  def persist!(reference, baseline, records)
    journal = { 'baseline' => baseline, 'records' => records }
    journal['signature'] = verifier.generate(binding(reference, journal), purpose: PURPOSE)
    @run.update!(settings: @run.settings.merge(KEY => journal))
  end

  def binding(reference, journal)
    { 'run_id' => @run.id, 'account_id' => @run.account_id, 'flow_id' => @run.flow_id, 'event_key' => @run.event_key,
      'scope' => reference.scope, 'stamp' => @run.settings.fetch(JrcRelationship::PlaybookFlow::STAMP_KEY), 'journal' => journal }
  end

  def digest(value)
    JrcRelationship::PlaybookFlowReference.digest(value)
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
