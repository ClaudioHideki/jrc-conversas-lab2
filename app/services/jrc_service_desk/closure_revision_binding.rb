# frozen_string_literal: true

# A prospective closure requirement revision. The ticket and every SLA cycle keep
# their original immutable policy binding; no historical row is replaced.
class JrcServiceDesk::ClosureRevisionBinding
  EVENT = 'closure_policy_revised'
  CLOSING = %w[resolve close].freeze
  attr_reader :ticket, :source, :target, :event

  def initialize(ticket, source)
    @ticket, @source = ticket, source
    @event = ticket.ticket_events.where(event_type: EVENT).order(id: :desc).first
    return unless event && source && event.data['source_version_id'] == source.id

    @target = JrcServiceDesk::LifecyclePolicyVersion.find_by(id: event.data['target_version_id'], account_id: ticket.account_id, unit_id: ticket.unit_id)
  end

  def self.proposal(source)
    raise ArgumentError, 'Contractual or specific requirements need an individual policy review' if source_reason(source)
    raise ArgumentError, 'Automatic calendar SLA is required' unless source.definition.dig('sla', 'mode') == 'calendar_snapshot'

    definition = source.definition.deep_dup
    definition['sla'].merge!('obligation' => 'operational', 'missing_configuration' => 'allow_operational_closure')
    definition['transitions'].each do |rule|
      next unless CLOSING.include?(rule['action'])
      rule['requirements'] = { 'note' => false, 'solution' => false, 'classification' => false, 'evidence' => false,
        'fields' => { 'closing_reason' => { 'type' => 'text', 'required' => true, 'label' => 'Motivo do encerramento' } } }
    end
    JrcServiceDesk::LifecycleRules.new(definition)
    definition
  end

  def self.source_reason(source)
    return 'contractual_policy' if source.definition.dig('sla', 'obligation') == 'contractual'
    specific = source.definition['transitions'].select { |r| CLOSING.include?(r['action']) }.any? do |rule|
      fields = rule['requirements']['fields']
      rule['requirements']['evidence'] || (fields.keys - ['closing_reason']).any? ||
        (fields['closing_reason'] && (fields['closing_reason']['type'] != 'text' || fields['closing_reason'].key?('equals')))
    end
    'specific_requirement' if specific
  end

  def self.pair_reason(source, target)
    return 'revision_incompatible' unless source && target && target.lifecycle_policy_id == source.lifecycle_policy_id &&
      target.account_id == source.account_id && target.unit_id == source.unit_id && target.version > source.version &&
      target.publication['enabled'] && source.status_phases == target.status_phases
    return source_reason(source) if source_reason(source)
    return 'revision_incompatible' unless source.definition.dig('sla', 'mode') == 'calendar_snapshot'
    return 'revision_incompatible' unless target.definition.dig('sla', 'obligation') == 'operational' &&
      target.definition.dig('sla', 'missing_configuration') == 'allow_operational_closure'

    expected = proposal(source)
    # The visible closing_reason label may be customized; its type and obligation may not.
    clean = lambda do |value|
      copy = value.deep_dup
      copy['transitions'].each { |r| r.dig('requirements', 'fields', 'closing_reason')&.delete('label') if CLOSING.include?(r['action']) }
      copy
    end
    'revision_incompatible' unless clean.call(expected) == clean.call(target.definition)
  end

  def self.ticket_reason(ticket)
    return 'terminal_ticket' unless %w[open waiting resolved].include?(ticket.status.phase)
    return 'contractual_ticket' if ticket.contract_id || ticket.service&.approval_required?
    return 'approval_pending' if ticket.ticket_approvals.where(status: %w[pending rejected returned]).exists?
    return 'contractual_ticket' if ticket.sla_snapshots.any? do |snapshot|
      conditions = snapshot.contract_conditions
      conditions.any? do |key, value|
        if %w[provisional contract_validated approved_contracts_identified].include?(key)
          key != 'provisional' && value == true
        else
          value.present?
        end
      end
    end
    nil
  end

  def active?
    target && event.data['source_digest'] == source.digest && event.data['target_digest'] == target.digest && !self.class.pair_reason(source, target) && !self.class.ticket_reason(ticket)
  end

  def rule(rule)
    active? && CLOSING.include?(rule['action']) ? target.rules.rule(rule['key']) : rule
  end

  def closure_rules
    active? ? target.rules : source.rules
  end

  def projection
    return nil unless event
    { source_version_id: event.data['source_version_id'].to_s, target_version_id: event.data['target_version_id'].to_s,
      target_version: target&.version, target_digest: event.data['target_digest'], batch_id: event.correlation_id, applied_at: event.created_at.iso8601(6), active: !!active? }
  end
end
