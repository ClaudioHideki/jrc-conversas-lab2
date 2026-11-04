class JrcApprovals::AdjustmentIntent
  REQUIRED = %i[changes mode reason expected_version idempotency_key].freeze
  OPTIONAL = %i[step_code delegation_id own_delegation_id].freeze
  attr_reader :changes, :mode, :reason, :expected_version, :idempotency_key, :step_code, :delegation_id, :own_delegation_id

  def initialize(input)
    raise JrcApprovals::Error, 'INVALID_INPUT' unless (REQUIRED - input.keys).empty? && (input.keys - REQUIRED - OPTIONAL).empty?

    @changes, @mode, @reason, @expected_version, @idempotency_key = input.values_at(*REQUIRED)
    @step_code, @delegation_id, @own_delegation_id = input.values_at(*OPTIONAL)
    validate!
    @reason = reason.strip
  end

  def digest(request_id)
    payload = { request_id: request_id, changes: changes, mode: mode, reason: reason,
                expected_version: expected_version, step_code: step_code, delegation_id: delegation_id }
    payload[:own_delegation_id] = own_delegation_id if own_delegation_id
    JrcApprovals::Ledger.digest(payload)
  end

  private

  def validate!
    JrcApprovals::Ledger.key!(idempotency_key)
    raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS' unless valid_changes? && %w[save approve].include?(mode)
    raise JrcApprovals::Error, 'REASON_REQUIRED' unless reason.is_a?(String) && reason.strip.present? && reason.bytesize <= 4096
  end

  def valid_changes?
    changes.is_a?(Hash) && changes.keys == ['discount_cents'] && changes['discount_cents'].is_a?(Integer) &&
      changes['discount_cents'].between?(0, JrcApprovals::TierRanges::MAX_EXACT_BOUND)
  end
end
