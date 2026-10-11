# Administrative attestations are not provider receipts. Unknown usage is never released.
class JrcNico::LegacyReservationReview
  class Conflict < StandardError; end
  OUTCOMES = %w[confirmed estimated not_executed unknown].freeze
  SOURCES = %w[recorded_usage external_receipt conservative_estimate runtime_not_executed investigation].freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def initialize(member:)
    @member = member
    @report = JrcNico::LegacyReservations.new(member: member)
  end

  def call(type:, id:, decision:, apply: false, authorized: false, simulation_token: nil)
    input = decision.deep_stringify_keys
    @authorized = authorized == true
    @report.account.with_lock do
      @report.authorize!(lock: true)
      @record = @report.record(type, id)
      @record.with_lock do
        digest = JrcNico::LegacyReservations.digest(input)
        prior = replay(input, digest, apply)
        next prior if prior

        @row = @report.describe(@record, type)
        validate!(input)
        raise Pundit::NotAuthorizedError if apply && !@authorized

        result = projection(input)
        proof = [digest, @row[:fingerprint], JrcNico::LegacyReservations.digest(@events.map(&:attributes))]
        verifier = Rails.application.message_verifier('nico-legacy-review')
        unless apply
          next result.merge('simulation_token' => verifier.generate(proof, purpose: 'individual-review', expires_in: 15.minutes))
        end
        valid = simulation_token.is_a?(String) && verifier.verified(simulation_token, purpose: 'individual-review') == proof
        raise Conflict, 'review_simulation_required_or_changed' unless valid

        persist!(input, digest, result)
      end
    end
  end

  private

  def replay(input, digest, apply)
    return unless apply

    matches = JrcNico::LegacyReservations::MODELS.values.flat_map do |model|
      model.where(account: @report.account).where('accounting @> ?', { legacy_reviews: [{ request_id: input['request_id'] }] }.to_json)
           .flat_map { |record| Array(record.accounting['legacy_reviews']).select { |entry| entry['request_id'] == input['request_id'] } }
    end
    return if matches.empty?

    prior = matches.first
    raise Conflict, 'review_request_conflict' unless prior['decision_digest'] == digest && prior['record_id'] == @record.id &&
                                                   prior['record_type'] == (@record.is_a?(JrcNico::Run) ? 'run' : 'inference') &&
                                                   prior['actor_account_user_id'] == @member.id

    raise Pundit::NotAuthorizedError unless @authorized

    prior.fetch('result').merge('replayed' => true)
  end

  def validate!(input)
    allowed = %w[request_id fingerprint classification source justification evidence usage_event_ids excluded_usage_event_ids
                 provider_id model usage conservative_upper_bound runtime_outcome]
    raise ArgumentError, 'invalid_review_fields' if (input.keys - allowed).any?
    raise ArgumentError, 'new_accounting_record' unless @row[:legacy]
    raise Conflict, 'review_snapshot_changed' unless input['fingerprint'] == @row[:fingerprint]
    active = @record.status == 'queued' || (@record.status == 'running' && (@record.lease_expires_at || (@record.created_at + 3.minutes)).future?)
    raise Conflict, 'operation_still_active' if active
    settled = @record.accounting.dig('legacy_review', 'classification')
    raise Conflict, 'legacy_review_already_settled' if settled && settled != 'unknown'
    raise ArgumentError, 'invalid_review_request' unless input['request_id'].is_a?(String) && UUID.match?(input['request_id'])
    raise ArgumentError, 'invalid_classification' unless OUTCOMES.include?(input['classification']) && SOURCES.include?(input['source'])
    justified = input['justification'].is_a?(String) && input['justification'].length.between?(20, 1000)
    raise ArgumentError, 'review_justification_required' unless justified

    evidence = input['evidence']
    valid = evidence.is_a?(Array) && evidence.size.between?(1, 10) && evidence.all? do |entry|
      entry.is_a?(Hash) && entry.keys.sort == %w[reference sha256] &&
        entry['reference'].is_a?(String) && /\A[a-zA-Z0-9_.:-]{1,120}\z/.match?(entry['reference']) &&
        entry['sha256'].is_a?(String) && /\A[0-9a-f]{64}\z/.match?(entry['sha256'])
    end
    raise ArgumentError, 'review_evidence_required' unless valid
    sensitive = /sk-[\w-]{12,}|Bearer\s|gh[pousr]_\w{15,}|github_pat_|-----BEGIN.*PRIVATE KEY/i
    raise ArgumentError, 'sensitive_review_content' if sensitive.match?(input.to_json)

    @events = JrcNico::ReservationLedger.new(@record).events.order(:id).to_a
    validate_source!(input)
  end

  def validate_source!(input)
    source, outcome = input.values_at('source', 'classification')
    if source == 'recorded_usage'
      validate_events!(input)
      expected = @events.any? { |event| event.metadata['usage_estimated'] == true } ? 'estimated' : 'confirmed'
      raise ArgumentError, 'receipt_classification_mismatch' unless outcome == expected
    else
      raise Conflict, 'usage_already_recorded' if @events.any?
      exact_request = @report.request_id(@record)
      if exact_request && @report.candidates_for(@record).where("metadata ->> 'request_id' = ?", exact_request).exists?
        raise Conflict, 'request_usage_requires_association'
      end
      ids = @row[:candidate_usage_events].map { |event| event[:id] }
      raise ArgumentError, 'candidate_events_require_review' unless input['excluded_usage_event_ids'].is_a?(Array) &&
                                                                  input['excluded_usage_event_ids'].sort == ids.sort
      if %w[external_receipt conservative_estimate].include?(source)
        validate_usage!(input)
        expected = source == 'external_receipt' ? 'confirmed' : 'estimated'
        raise ArgumentError, 'receipt_classification_mismatch' unless outcome == expected
        raise ArgumentError, 'conservative_estimate_required' if outcome == 'estimated' && input['conservative_upper_bound'] != true
        if outcome == 'estimated' && input['usage']['total_tokens'] < @record.reserved_tokens
          raise ArgumentError, 'estimate_cannot_lower_unknown_bound'
        end
      elsif source == 'runtime_not_executed'
        raise ArgumentError, 'non_execution_proof_required' unless outcome == 'not_executed' &&
                                                                %w[not_dispatched rejected_before_provider].include?(input['runtime_outcome'])
      else
        raise ArgumentError, 'unknown_must_remain_reserved' unless outcome == 'unknown'
      end
    end
    raise ArgumentError, 'unexpected_usage_payload' if !%w[external_receipt conservative_estimate].include?(source) && input.key?('usage')
  end

  def validate_events!(input)
    ids = input['usage_event_ids']
    valid_ids = ids.is_a?(Array) && ids.any? && ids.all? { |id| id.is_a?(Integer) && id.positive? } && ids.uniq == ids
    raise ArgumentError, 'invalid_usage_events' unless valid_ids

    selected = @report.account.jrc_ai_usage_events.where(id: ids).order(:id).to_a
    raise ArgumentError, 'invalid_usage_events' unless selected.size == ids.size && (@events.map(&:id) - ids).empty?

    key = @record.is_a?(JrcNico::Run) ? 'run_id' : 'inference_id'
    selected.each do |event|
      event.lock!
      correct_agent = event.agent_key == (@record.is_a?(JrcNico::Run) ? @record.agent_key : 'nico')
      correct_feature = @record.is_a?(JrcNico::Run) ? event.feature == 'assisted_analysis' : event.feature.start_with?('nico_')
      correct_scope = event.provider_id.nil? || @report.account.jrc_ai_providers.exists?(id: event.provider_id)
      raise ArgumentError, 'invalid_usage_events' unless correct_agent && correct_feature && correct_scope &&
                                                        event.created_at.strftime('%Y-%m') == @row[:period] &&
                                                        (event.user_id == @record.user_id || @events.map(&:id).include?(event.id))
      %w[run_id inference_id].each do |correlation|
        value = event.metadata[correlation]
        raise Conflict, 'usage_event_already_associated' if value.present? && (correlation != key || value.to_s != @record.id.to_s)
      end
      request = @report.request_id(@record)
      if request && event.metadata['request_id'].present? && event.metadata['request_id'] != request
        raise Conflict, 'usage_request_mismatch'
      end
      raise ArgumentError, 'invalid_usage_events' unless event.input_tokens + event.output_tokens == event.total_tokens
    end
    @events = selected
  end

  def validate_usage!(input)
    usage = input['usage']
    valid = usage.is_a?(Hash) && usage.keys.sort == %w[input_tokens output_tokens total_tokens] &&
            usage.values.all? { |n| n.is_a?(Integer) && n.between?(0, 270_000) } &&
            usage['total_tokens'].positive? && usage['input_tokens'] + usage['output_tokens'] == usage['total_tokens']
    raise ArgumentError, 'invalid_review_usage' unless valid && input['model'].is_a?(String) && input['model'].length.between?(1, 150)
    raise ArgumentError, 'invalid_review_provider' unless @report.account.jrc_ai_providers.exists?(id: input['provider_id'])
  end

  def projection(input)
    new_usage = input.fetch('usage', {}).fetch('total_tokens', 0)
    released = input['classification'] != 'unknown'
    { account_id: @report.account.id, record_type: @row[:type], record_id: @record.id, classification: input['classification'],
      dry_run: true, fingerprint: @row[:fingerprint], previous_reserved_tokens: @record.reserved_tokens,
      resulting_reserved_tokens: released ? 0 : @record.reserved_tokens, new_usage_tokens: new_usage,
      reused_usage_event_ids: @events.map(&:id), reused_usage_tokens: @events.sum(&:total_tokens),
      period: @row[:period], consumption_is_estimated: input['classification'] == 'estimated' }.stringify_keys
  end

  def persist!(input, digest, result)
    key = @row[:type] == 'run' ? 'run_id' : 'inference_id'
    if %w[external_receipt conservative_estimate].include?(input['source'])
      event = JrcAi::UsageEvent.create!(account: @report.account, user: @record.user, provider_id: input['provider_id'],
                                       agent_key: @record.is_a?(JrcNico::Run) ? @record.agent_key : 'nico',
                                       feature: @record.is_a?(JrcNico::Run) ? 'assisted_analysis' : 'nico_legacy_review', model: input['model'],
                                       **input.fetch('usage').symbolize_keys, created_at: @record.created_at,
                                       metadata: { key => @record.id, legacy_review_request_id: input['request_id'], cost_available: false,
                                                   usage_estimated: input['classification'] == 'estimated', administrative_attestation: true })
      result['created_usage_event_id'] = event.id
    elsif input['source'] == 'recorded_usage'
      @events.each { |event| event.update!(metadata: event.metadata.merge(key => @record.id)) }
    end
    result['dry_run'] = false
    result['applied_at'] = Time.current.iso8601(6)
    audit = input.merge('policy' => 'nico-legacy-review-v1', 'actor_account_user_id' => @member.id, 'actor_user_id' => @member.user_id,
                        'explicitly_authorized' => true, 'decision_digest' => digest, 'record_type' => @row[:type], 'record_id' => @record.id,
                        'previous_status' => @record.status, 'previous_reserved_tokens' => @record.reserved_tokens, 'result' => result)
    @record.accounting = @record.accounting.merge('basis' => input['classification'], 'legacy_review' => audit,
                                                 'legacy_reviews' => Array(@record.accounting['legacy_reviews']) + [audit],
                                                 'reconciliation_history' => Array(@record.accounting['reconciliation_history']) + [audit])
    @record.reserved_tokens = result['resulting_reserved_tokens']
    if @record.is_a?(JrcNico::Inference) && @record.status != 'completed'
      @record.status = input['classification'] == 'unknown' ? 'unknown' : 'failed'
    elsif @record.is_a?(JrcNico::Run) && @record.status == 'running'
      @record.assign_attributes(status: 'failed', error_code: 'legacy_reviewed_outcome', finished_at: Time.current)
    end
    @record.save!
    result
  end
end
