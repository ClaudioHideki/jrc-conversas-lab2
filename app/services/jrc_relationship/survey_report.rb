require 'csv'

class JrcRelationship::SurveyReport
  IDENTITIES = %w[assignment_id company_id contact_id owner_id agent_id team_id contract_id product_id definition_id rule_id record_id].freeze
  VALUES = {
    'type' => ['kind', %w[nps csat ces custom]],
    'classification' => ['classification', %w[detractor neutral promoter low satisfied unclassified]],
    'treatment_status' => ['treatment_status', %w[untreated in_progress treated]],
    'source_type' => ['source_type', JrcRelationship::SurveySource::TYPES]
  }.freeze
  CHANNELS = { 'email' => %w[email Channel::Email], 'whatsapp' => %w[whatsapp Channel::Whatsapp Channel::TwilioSms],
               'public_link' => ['public_link'] }.freeze
  HEADERS = %w[id customer type source_type source_id cycle_key rule_version definition_version contact_id agent_id team_id
               contract_id product_id classification score answers comment responded_at treatment_status treatment_cause treated_at
               enrolled_at delivery_status attempts sent_at delivered_at expires_at eligible_decision_id period_basis].freeze
  CSV_SOURCE_FIELDS = %w[source_type source_id cycle_key rule_version definition_version contact_id agent_id team_id
                         contract_id product_id classification score].freeze

  def initialize(context, filters = {})
    @context = context
    @filters = filters.to_h.stringify_keys
  end

  def scope
    raise ArgumentError, 'Invalid survey period basis' unless %w[response cohort].include?(period_basis)

    rows = @context.records(JrcRelationship::Survey)
    rows = identities(rows)
    rows = values(rows)
    rows = response_state(rows)
    rows = response_period(rows)
    rows = scores(rows)
    rows = origin_filters(rows)
    rows = portfolio_filters(rows)
    customer_search(rows)
  end

  def csv
    rows = period_basis == 'cohort' ? scope : scope.where.not(responded_at: nil)
    rows = rows.includes(:assignment, :company, :contact).order(id: :asc)
    raise ArgumentError, 'Select a smaller response period (maximum 10000 responses)' if rows.limit(10_001).count > 10_000

    CSV.generate do |output|
      output << HEADERS
      rows.each { |survey| output << csv_row(survey).map { |value| csv_value(value) } }
    end
  end

  def cohort_scope
    filters = @filters.except('classification', 'treatment_status', 'record_status', 'score_min', 'score_max')
    filters = filters.except('from', 'to') if period_basis == 'response'
    self.class.new(@context, filters.merge('period_basis' => 'cohort')).scope
  end

  def period_basis
    @filters['period_basis'].presence || 'response'
  end

  def cohort_available?
    period_basis == 'cohort' || @filters['from'].blank?
  end

  def cohort_period
    { basis: @filters['from'].present? ? period_basis : 'all_time_enrollment',
      from: @filters['from'].presence, to: (@filters['to'].presence || @filters['from'].presence) }
  end

  private

  def identities(rows)
    IDENTITIES.each do |key|
      rows = rows.where((key == 'record_id' ? 'id' : key) => positive_id(@filters[key])) if @filters[key].present?
    end
    rows
  end

  def values(rows)
    VALUES.each do |key, (column, choices)|
      next if @filters[key].blank?

      raise ArgumentError, "Invalid survey #{key}" unless choices.include?(@filters[key])

      rows = rows.where(column => @filters[key])
    end
    rows
  end

  def response_state(rows)
    case @filters['record_status'].presence
    when nil then rows
    when 'responded' then rows.where.not(responded_at: nil)
    when 'awaiting' then rows.where(responded_at: nil).where('expires_at > ?', Time.current)
    when 'expired' then rows.where(responded_at: nil).where('expires_at <= ?', Time.current)
    when 'scheduled', 'available', 'queued', 'dispatching', 'sent', 'delivered', 'failed', 'blocked', 'unknown'
      rows.where(status: @filters['record_status'])
    else raise ArgumentError, 'Invalid survey state'
    end
  end

  def response_period(rows)
    raise ArgumentError, 'Select the response period start' if @filters['from'].blank? && @filters['to'].present?
    return rows if @filters['from'].blank?

    rows.where((period_basis == 'cohort' ? :created_at : :responded_at) => response_dates)
  end

  def response_dates
    from = Date.iso8601(@filters['from'])
    to = Date.iso8601(@filters['to'].presence || @filters['from'])
    raise ArgumentError, 'Invalid response period' if to < from || (to - from).to_i > 366

    from.beginning_of_day..to.end_of_day
  end

  def scores(rows)
    %w[score_min score_max].each do |key|
      next if @filters[key].blank?

      score = Float(@filters[key])
      raise ArgumentError, 'Invalid response score' unless score.finite? && score.between?(0, 100)

      rows = rows.where("score #{key == 'score_min' ? '>=' : '<='} ?", score)
    end
    rows
  end

  def origin_filters(rows)
    if @filters['business_unit_id'].present?
      assignments = @context.assignments.where(business_unit_id: positive_id(@filters['business_unit_id']))
      rows = rows.where(assignment_id: assignments.select(:id))
    end
    rows = rows.where("metadata ->> 'unit_id' = ?", positive_id(@filters['unit_id']).to_s) if @filters['unit_id'].present?
    if @filters['channel'].present?
      raise ArgumentError, 'Invalid survey channel' unless %w[same email whatsapp public_link].include?(@filters['channel'])

      rows = channel_scope(rows)
    end
    rows
  end

  def channel_scope(rows)
    return rows.where("rule_snapshot -> 'settings' ->> 'channel' = 'same'") if @filters['channel'] == 'same'

    rows.where("COALESCE(metadata ->> 'sent_channel', rule_snapshot -> 'settings' ->> 'channel', 'public_link') IN (?)",
               CHANNELS.fetch(@filters['channel']))
  end

  def customer_search(rows)
    return rows if @filters['q'].blank?

    query = "%#{ActiveRecord::Base.sanitize_sql_like(@filters['q'].to_s.first(100))}%"
    rows.left_joins(:company, :contact).where('companies.name ILIKE ? OR contacts.name ILIKE ?', query, query)
  end

  def portfolio_filters(rows)
    keys = %w[portfolio_owner_id portfolio_status segment_id complexity]
    return rows unless keys.any? { |key| @filters[key].present? } || %w[mine unassigned].include?(@filters['mode'])

    assignments = portfolio_owner_scope
    assignments = portfolio_status_scope(assignments)
    %w[segment_id complexity].each do |key|
      assignments = assignments.where('settings ->> ? = ?', key, @filters[key].to_s) if @filters[key].present?
    end
    rows.where(assignment_id: assignments.select(:id))
  end

  def portfolio_owner_scope
    rows = @context.assignments
    rows = rows.where(owner_id: @context.user.id) if @filters['mode'] == 'mine'
    rows = rows.where(owner_id: nil) if @filters['mode'] == 'unassigned'
    rows = rows.where(owner_id: positive_id(@filters['portfolio_owner_id'])) if @filters['portfolio_owner_id'].present?
    rows
  end

  def portfolio_status_scope(assignments)
    if @filters['portfolio_status'].present?
      raise ArgumentError, 'Invalid portfolio status' unless %w[onboarding active at_risk churned inactive].include?(@filters['portfolio_status'])

      assignments = assignments.where(status: @filters['portfolio_status'])
    end
    assignments
  end

  def positive_id(value)
    raise ArgumentError, 'Invalid survey identity filter' unless value.to_s.match?(/\A[1-9]\d{0,18}\z/)

    value.to_i
  end

  def csv_row(survey)
    [survey.id, customer_label(survey), survey.kind] + CSV_SOURCE_FIELDS.map { |key| survey.public_send(key) } +
      response_values(survey) + delivery_values(survey)
  end

  def response_values(survey)
    [survey.answers.to_json, survey.comment, survey.responded_at&.iso8601,
     survey.treatment_status, survey.treatment_cause, survey.treated_at&.iso8601]
  end

  def delivery_values(survey)
    [survey.created_at.iso8601, survey.status, survey.attempts, survey.sent_at&.iso8601,
     survey.delivered_at&.iso8601, survey.expires_at.iso8601, eligible_decision_id(survey), period_basis]
  end

  def eligible_decision_id(survey)
    JrcRelationship::SurveyDispatchDecision.where(account: @context.account, survey: survey, state: 'scheduled', reason: 'eligible').pick(:id)
  end

  def customer_label(survey)
    survey.assignment&.label || survey.company&.name || survey.contact&.name
  end

  def csv_value(value)
    return value unless value.is_a?(String)

    # Quoting alone does not prevent spreadsheet formula execution when a CSV is opened.
    value.match?(/\A(?:[=+\-@\t\r\n]|\s+[=+\-@])/) ? "'#{value}" : value
  end
end
