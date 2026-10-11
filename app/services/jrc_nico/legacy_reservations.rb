class JrcNico::LegacyReservations
  MODELS = { 'inference' => JrcNico::Inference, 'run' => JrcNico::Run }.freeze

  def self.digest(value)
    canonical = lambda do |item|
      if item.is_a?(Hash)
        item.stringify_keys.sort.to_h.transform_values { |child| canonical.call(child) }
      elsif item.is_a?(Array)
        item.map { |child| canonical.call(child) }
      else
        item
      end
    end
    Digest::SHA256.hexdigest(canonical.call(value).to_json)
  end

  def initialize(member:)
    @member = member
    authorize!
  end

  def authorize!(lock: false)
    current = AccountUser.find(@member.id)
    current.lock! if lock
    raise Pundit::NotAuthorizedError unless current.account_id == @member.account_id && current.administrator?

    @member = current
  end

  def account
    @member.account
  end

  def record(type, id)
    MODELS.fetch(type) { raise ArgumentError, 'invalid_record_type' }.where(account: account).find(id)
  end

  def report(period:)
    authorize!
    raise ArgumentError, 'invalid_period' unless period.is_a?(String) && /\A\d{4}-(0[1-9]|1[0-2])\z/.match?(period)

    month = Time.zone.strptime(period, '%Y-%m')
    account.with_lock do
      authorize!(lock: true)
      rows = MODELS.flat_map do |type, model|
        model.where(account: account, created_at: month.all_month).where("accounting ->> 'version' IS NULL")
             .where("reserved_tokens > 0 OR accounting ? 'legacy_reviews'").order(:id).map { |value| describe(value, type) }
      end
      usage = account.jrc_ai_usage_events.where(created_at: month.all_month, agent_key: JrcNico::AgentCatalog::KEYS)
      { account_id: account.id, period: period, timezone: Time.zone.name, dry_run: true, count: rows.size,
        used_tokens: usage.sum(:total_tokens), legacy_reserved_tokens: rows.sum { |row| row[:reserved_tokens] },
        effective_legacy_reserved_tokens: rows.select { |row| row[:usage_events].empty? }.sum { |row| row[:reserved_tokens] },
        classified: rows.group_by { |row| row[:classification] }.transform_values(&:size), records: rows }
    end
  end

  def describe(value, type)
    raise Pundit::NotAuthorizedError unless value.account_id == account.id

    events = JrcNico::ReservationLedger.new(value).events.order(:id).to_a
    candidates = candidates_for(value).order(:id).to_a
    classification = if events.any?
                       events.any? { |event| event.metadata['usage_estimated'] == true } ? 'estimated' : 'confirmed'
                     else
                       value.accounting.dig('legacy_review', 'classification') || 'unknown'
                     end
    { account_id: account.id, type: type, id: value.id, legacy: value.accounting['version'].nil?, status: value.status,
      created_at: value.created_at, period: value.created_at.strftime('%Y-%m'), reserved_tokens: value.reserved_tokens,
      classification: classification, automatically_releasable: false, request_id: request_id(value),
      usage_events: events.map { |event| event_summary(event) },
      candidate_usage_events: candidates.map { |event| event_summary(event).merge(correlation: 'candidate_only_not_proof') },
      reconciliation_history: Array(value.accounting['reconciliation_history']), legacy_reviews: Array(value.accounting['legacy_reviews']),
      fingerprint: fingerprint(value, events, candidates) }
  end

  def candidates_for(value)
    raise Pundit::NotAuthorizedError unless value.account_id == account.id

    key = value.is_a?(JrcNico::Run) ? 'run_id' : 'inference_id'
    scope = account.jrc_ai_usage_events.where(agent_key: value.is_a?(JrcNico::Run) ? value.agent_key : 'nico')
    scope = scope.where(value.is_a?(JrcNico::Run) ? "feature = 'assisted_analysis'" : "feature LIKE 'nico_%'")
    scope = scope.where("metadata ->> ? IS NULL", key)
    nearby = scope.where(user_id: value.user_id, created_at: (value.created_at - 3.minutes)..(value.created_at + 3.minutes))
    request_id(value) ? nearby.or(scope.where("metadata ->> 'request_id' = ?", request_id(value))) : nearby
  end

  def request_id(value)
    value.accounting['request_id'] || (value.request_id if value.is_a?(JrcNico::Run))
  end

  private

  def fingerprint(value, events, candidates)
    data = [value.attributes.slice('id', 'account_id', 'status', 'reserved_tokens', 'created_at', 'updated_at', 'accounting', 'lease_expires_at'),
            (events + candidates).map { |event| event.attributes }.sort_by { |event| event['id'] }]
    self.class.digest(data)
  end

  def event_summary(event)
    { id: event.id, provider_id: event.provider_id, model: event.model, input_tokens: event.input_tokens,
      output_tokens: event.output_tokens, total_tokens: event.total_tokens, created_at: event.created_at,
      period: event.created_at.strftime('%Y-%m'), estimated: event.metadata['usage_estimated'] == true }
  end
end
