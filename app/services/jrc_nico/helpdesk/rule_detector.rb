# Deterministic facts only. Text flags preserve evidence and route to humans; they do not authorize a tool.
class JrcNico::Helpdesk::RuleDetector
  DETECTORS = {
    'R01' => :recurrence, 'R02' => :repeated, 'R03' => :repeated, 'R04' => :mass, 'R05' => :prealert, 'R06' => :breached,
    'R07' => :late_hours, 'R08' => :late_hours, 'R09' => :late_days, 'R10' => :complaint, 'R11' => :legal, 'R12' => :critical,
    'R13' => :inactivity, 'R14' => :reopening, 'R15' => :survey, 'R16' => :classification
  }.freeze
  def initialize(definition:, facts:)
    @definition = definition
    @facts = facts
  end

  def call
    @definition.fetch('rules').filter_map do |key, rule|
      next unless rule.fetch('enabled')

      detail = detect(key, rule)
      { rule_key: key, evidence: detail } if detail
    end
  end

  private

  def detect(key, rule)
    # Only this fixed server-side map selects a detector; customer text never selects a method.
    send(DETECTORS.fetch(key), rule)
  end

  def defect?
    @facts['case_kind'] == 'defect' && @facts['defect_key'].present?
  end

  def same_customer_defect?(item)
    item['company_id'] == @facts['company_id'] && item['defect_key'] == @facts['defect_key']
  end

  def recurrence_window?(item, seconds)
    item['open'] || item['closed_age_seconds']&.between?(0, seconds)
  end

  def recurrence(rule)
    return unless defect? && @facts['company_id']

    previous = @facts.fetch('previous_cases', []).select do |item|
      same_customer_defect?(item) && recurrence_window?(item, rule.fetch('window_days') * 86_400)
    end
    { 'previous_ticket_ids' => previous.map { |item| item.fetch('id') }.sort } if previous.any?
  end

  def repeated(rule)
    return unless defect? && @facts['company_id']

    cases = @facts.fetch('occurrences', []).select do |item|
      same_customer_defect?(item) && item['age_seconds'].between?(0, rule.fetch('window_days') * 86_400)
    end
    ids = cases.map { |item| item.fetch('id') }.uniq.sort
    { 'occurrence_ids' => ids, 'count' => ids.size } if ids.size >= rule.fetch('count')
  end

  def mass(rule)
    return unless defect?

    cases = @facts.fetch('occurrences', []).select do |item|
      mass_case?(item, rule)
    end
    count = cases.pluck('company_id').uniq.size
    { 'ticket_ids' => cases.pluck('id').uniq.sort, 'company_count' => count } if count >= rule.fetch('count')
  end

  def mass_case?(item, rule)
    item['company_id'] && item['defect_key'] == @facts['defect_key'] && item['age_seconds'].between?(0, rule.fetch('window_minutes') * 60)
  end

  def prealert(rule)
    elapsed, budget = @facts.values_at('sla_elapsed_seconds', 'sla_budget_seconds')
    return unless @facts['sla_running'] && elapsed && budget&.positive? && elapsed >= budget * rule.fetch('percent') / 100.0 && elapsed < budget

    { 'clock_id' => @facts.fetch('clock_id'), 'percent' => rule.fetch('percent'), 'due_at' => @facts.fetch('due_at') }
  end

  def overdue(seconds, basis)
    value = @facts[basis == 'business' ? 'overdue_business_seconds' : 'overdue_calendar_seconds']
    return unless @facts['sla_running'] && value && value > seconds

    { 'clock_id' => @facts.fetch('clock_id'), 'overdue_seconds' => value, 'basis' => basis, 'due_at' => @facts.fetch('due_at') }
  end

  def breached(_rule)
    overdue(0, 'calendar')
  end

  def late_hours(rule)
    overdue(rule.fetch('hours') * 3600, rule.fetch('basis'))
  end

  def late_days(rule)
    overdue(rule.fetch('days') * 86_400, rule.fetch('basis'))
  end

  def keyword_match(rule)
    text = @facts.fetch('customer_text', '').downcase
    words = text.scan(/[[:alnum:]_]+/)
    matches = rule.fetch('keywords').select { |word| words.include?(word.downcase) }
    matches += rule.fetch('phrases').select { |phrase| text.include?(phrase.downcase) }
    matches
  end

  def complaint(rule)
    matches = keyword_match(rule)
    low_nps = @facts['survey_model'] == 'nps' && @facts['survey_scale'] == '0-10' && @facts['survey_score'].is_a?(Numeric) &&
              @facts['survey_score'].between?(0, 6)
    return if matches.empty? && !low_nps && !@facts['survey_recovery_id']

    { 'matched_terms' => matches, 'evidence_note_ids' => @facts.fetch('customer_note_ids', []),
      'survey_id' => @facts['survey_id'], 'existing_recovery_id' => @facts['survey_recovery_id'] }.compact
  end

  def legal(rule)
    matches = keyword_match(rule)
    { 'matched_terms' => matches, 'evidence_note_ids' => @facts.fetch('customer_note_ids', []), 'internal_only' => true } if matches.any?
  end

  def critical(rule)
    return unless @facts['case_kind'] == 'defect' && rule.fetch('critical_company_ids').include?(@facts['company_id'])

    { 'company_id' => @facts['company_id'] }
  end

  def inactivity(rule)
    days = @facts['inactive_seconds']&./(86_400.0)
    return unless days && @facts['open']

    levels = rule.fetch('days').each_with_index.filter_map { |threshold, index| index + 1 if days >= threshold }
    { 'level' => levels.max, 'inactive_days' => days, 'anchor' => @facts.fetch('last_relevant_at') } if levels.any?
  end

  def reopening(_rule)
    eligible = @facts['phase'] == 'closed' || (@facts['phase'] == 'waiting' && @facts['waiting_for_approval'] == true)
    return unless eligible && @facts['negative_return'] == true

    detail = { 'same_ticket_id' => @facts.fetch('ticket_id'), 'cycle_key' => @facts.fetch('cycle_key'), 'requires_lifecycle_rule' => true }
    detail.merge(@facts.slice(*JrcNico::Helpdesk::CycleEvidence::FIELDS))
  end

  def survey(_rule)
    return unless @facts['trigger'] == 'closed'

    { 'cycle_key' => @facts.fetch('cycle_key'), 'survey_decision_id' => @facts['survey_decision_id'],
      'survey_id' => @facts['survey_id'], 'single_engine' => 'JrcRelationship::SurveyEngine' }.compact
  end

  def classification(_rule)
    missing = %w[service_id ticket_type_id case_kind priority_id].select { |key| @facts[key].blank? }
    { 'missing' => missing, 'human_review' => true } if @facts['trigger'] == 'created' && missing.any?
  end
end
