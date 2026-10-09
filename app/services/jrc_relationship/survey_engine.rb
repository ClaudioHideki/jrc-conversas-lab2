require 'digest'

class JrcRelationship::SurveyEngine
  def self.evaluate_closure(source:, cycle_key:, contract_id: nil, product_id: nil)
    references = { contract_id: contract_id, product_id: product_id }
    return new(source: source, cycle_key: cycle_key, **references).call unless enabled?(source.account)

    chosen = closure_rule(source, cycle_key, references)
    # Execution identity is explicitly configured on the chosen policy, never an account administrator inferred by the job.
    new(source: source, cycle_key: cycle_key, member: chosen&.execution_member, **references).call
  end

  def self.closure_rule(source, cycle_key, references)
    rules = JrcRelationship::SurveyRule.where(account_id: source.account_id).includes(:execution_member, :definition)
    candidates = rules.filter_map do |rule|
      next unless closure_candidate?(rule, source)

      new(source: source, cycle_key: cycle_key, member: rule.execution_member, **references).preview[:rule]
    end
    candidates.max_by { |rule| [rule.specificity, rule.priority, rule.version, rule.id] }
  end

  def self.closure_candidate?(rule, source)
    rule.execution_member && (rule.matchers['source_type'].blank? || rule.matchers['source_type'] == source.class.name)
  end
  private_class_method :closure_rule, :closure_candidate?

  def self.enabled?(account)
    account.active? && account.feature_enabled?('jrc_relationship') &&
      JrcRelationship::Configuration.find_by(account_id: account.id, scope_key: 'account')&.effective_rules&.fetch('survey_automation_enabled',
                                                                                                                   false) == true
  end

  def self.native_csat_response(response)
    survey = JrcRelationship::Survey.where(account_id: response.account_id, kind: 'csat')
                                    .where("metadata ->> 'sent_message_id' = ?", response.message_id.to_s).first
    return unless survey

    JrcRelationship::SurveyResponse.new(survey).call(answers: { survey.questions.first.fetch('key') => response.rating },
                                                     comment: response.feedback_message, native_response_id: response.id)
  end

  def initialize(source:, cycle_key:, member: nil, contract_id: nil, product_id: nil)
    @source = source
    @cycle_key = cycle_key.to_s
    @member = member
    @commercial_ids = { contract_id: contract_id, product_id: product_id }
    raise ArgumentError, 'Invalid closure cycle' unless @cycle_key.length.between?(1, 180)
    raise ArgumentError, 'Unsupported survey source' unless source.persisted? && JrcRelationship::SurveySource::TYPES.include?(source.class.name)

    @account = source.account
  end

  def call
    @account.with_lock do
      # Rule selection, its version, frequency and dedupe key belong to the same tenant transaction.
      result = preview
      key = evaluation_key(result)
      decision = JrcRelationship::SurveyDispatchDecision.find_or_initialize_by(account_id: @account.id, evaluation_key: key)
      next decision if decision.persisted?

      persist_decision!(decision, frequency_result(result))
    end
  end

  def preview(ignore_activation: false)
    return { state: 'skipped', reason: 'automation_disabled' } unless ignore_activation || self.class.enabled?(@account)

    membership = execution_membership
    return { state: 'blocked', reason: 'execution_member_missing' } unless membership

    context = JrcRelationship::Context.new(membership)
    origin = JrcRelationship::SurveySource.new(@source, context, **@commercial_ids)
    rule = matching_rule(origin)
    return { state: 'skipped', reason: 'rule_missing' } unless rule

    eligibility_result(origin, rule, membership)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    { state: 'blocked', reason: 'source_access_denied' }
  end

  private

  def execution_membership
    AccountUser.find_by(id: @member.id, account_id: @account.id, user_id: @member.user_id) if @member
  end

  def eligibility_result(origin, rule, membership)
    state, reason = origin_eligibility(origin) || rule_eligibility(rule, membership) || contact_eligibility(origin, rule) || %w[scheduled eligible]
    { rule: rule, source: origin, state: state, reason: reason }
  end

  def matching_rule(origin)
    attributes = origin.attributes
    rows = JrcRelationship::SurveyRule.where(account_id: @account.id).includes(:definition).to_a
    rows.select { |row| row.matchers.all? { |key, value| value.to_s == attributes[key].to_s } }
        .max_by { |row| [row.specificity, row.priority, row.version, row.id] }
  end

  def origin_eligibility(origin)
    return %w[skipped interaction_not_completed] unless origin.completed?
    return %w[blocked contact_missing] unless origin.contact

    nil
  end

  def rule_eligibility(rule, membership)
    return %w[skipped rule_disabled] unless rule.active && rule.definition.status == 'active'
    return %w[blocked execution_member_mismatch] unless rule.execution_member_id == membership.id
    return %w[skipped definition_not_available] unless rule.definition.available_at?(rule.effective_settings['delay_minutes'].minutes.from_now)

    nil
  end

  def contact_eligibility(origin, rule)
    return %w[skipped contact_blocked] if origin.contact.blocked?
    return %w[skipped consent_missing] if rule.effective_settings['consent_required'] && origin.contact.custom_attributes['survey_consent'] != true

    nil
  end

  def evaluation_key(result)
    policy_key = result[:rule] ? "#{result[:rule].id}:#{result[:rule].version}" : result[:reason]
    Digest::SHA256.hexdigest([@source.class.name, @source.id, @cycle_key, policy_key].join(':'))
  end

  def frequency_result(result)
    return result unless result[:state] == 'scheduled' && frequency_exceeded?(result[:rule], result[:source])

    result.merge(state: 'skipped', reason: 'frequency_exceeded')
  end

  def persist_decision!(decision, result)
    survey = build_survey!(result[:rule], result[:source]) if result[:state] == 'scheduled'
    decision.update!(source_type: @source.class.name, source_id: @source.id, cycle_key: @cycle_key,
                     state: result[:state], reason: result[:reason], rule: result[:rule], rule_version: result[:rule]&.version,
                     survey: survey, evaluated_at: Time.current)
    decision
  end

  def frequency_exceeded?(rule, origin)
    days = rule.effective_settings['frequency_days']
    return false if days.zero?

    rows = JrcRelationship::Survey.where(account_id: @account.id).where('created_at > ?', days.days.ago)
                                  .where.not(status: %w[failed blocked unknown])
    rows.exists?(frequency_identity(rule, origin))
  end

  def frequency_identity(rule, origin)
    contact_id = { contact_id: origin.contact.id }
    case rule.effective_settings['frequency_scope']
    when 'company' then origin.contact.company_id ? { company_id: origin.contact.company_id } : contact_id
    when 'contact' then contact_id
    else contact_id.merge(kind: rule.definition.kind)
    end
  end

  def build_survey!(rule, origin)
    scheduled_at = rule.effective_settings['delay_minutes'].minutes.from_now
    attributes = origin_attributes(origin).merge(policy_attributes(rule))
    attributes[:metadata]['question'] = rule.definition.questions.first['text']
    attributes.merge!(token_digest: Digest::SHA256.hexdigest(SecureRandom.hex(32)), status: 'scheduled', scheduled_at: scheduled_at,
                      expires_at: scheduled_at + rule.effective_settings['expires_hours'].hours)
    limit_definition_expiry!(attributes, rule.definition)
    JrcRelationship::Survey.create!(attributes)
  end

  def limit_definition_expiry!(attributes, definition)
    until_at = definition.settings['available_until'].presence
    attributes[:expires_at] = [attributes[:expires_at], Time.iso8601(until_at)].min if until_at
  end

  def origin_attributes(origin)
    { account: @account, assignment: origin.assignment, company_id: origin.contact.company_id, contact: origin.contact,
      contract: origin.contract, product: origin.product,
      owner: origin.assignment&.owner, agent_id: source_agent_id, team_id: origin.attributes['team_id'],
      source_type: @source.class.name, source_id: @source.id, cycle_key: @cycle_key,
      metadata: { 'unit_id' => origin.attributes['unit_id'], 'inbox_id' => origin.attributes['inbox_id'],
                  'attendance_origin' => origin.attendance_origin_signature,
                  'commercial_origin' => origin.commercial_origin_signature } }
  end

  def policy_attributes(rule)
    { execution_member_id: rule.execution_member_id, kind: rule.definition.kind, definition: rule.definition, rule: rule,
      rule_version: rule.version, definition_version: rule.definition.version,
      definition_snapshot: rule.definition.snapshot, rule_snapshot: rule.snapshot }
  end

  def source_agent_id
    @source.try(:assignee_id) || @source.try(:accepted_by_agent_id) || @source.try(:assignee_account_user)&.user_id ||
      (@source.user_id if @source.is_a?(JrcCrm::Activity))
  end
end
