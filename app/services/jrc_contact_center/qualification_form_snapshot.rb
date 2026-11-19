# frozen_string_literal: true

# Captures only pins applicable to the new qualification's already-frozen native rule context.
class JrcContactCenter::QualificationFormSnapshot
  # Compatibility choices already offered by the native operational editor; not another catalogue.
  LEGACY_REASON_CODES_V1 = %w[resolved information order callback transfer].freeze

  def self.capture!(record)
    new(record).capture!
  end

  def initialize(record)
    @record = record
  end

  def capture!
    return unless @record.channel == 'voice'

    bindings = JrcContactCenter::AcwFormBindingPolicy.new(account: @record.account).call
    return if bindings.empty?

    origin = JrcContactCenter::AcwQualificationPolicy.new(@record).snapshot
    raise JrcContactCenter::OperationError, 'invalid_acw_rule_snapshot' unless origin

    applicable = bindings.select { |row| origin.fetch('rules').pluck('id').include?(row.fetch('rule_id')) }
    return if applicable.empty?

    validator = JrcContactCenter::AcwFormBindings.new(account: @record.account)
    pins = validator.references!(applicable, rules: origin.fetch('rules'))
    validator.verify_metadata!(pins)
    reasons = (LEGACY_REASON_CODES_V1 + origin.fetch('rules').pluck('reason_code')).uniq.sort
    JrcContactCenter::QualificationForm.create!(
      account: @record.account, qualification: @record, **original_scope(origin),
      snapshot: { 'version' => 1, 'origin' => origin, 'bindings' => pins, 'reason_codes' => reasons }, answers: {}
    )
  end

  def original_scope(origin)
    queue = JrcContactCenter::Queue.where(account: @record.account).find(origin.fetch('queue_id')) if origin.fetch('queue_id')
    { unit_id: queue ? queue.unit_id : @record.call_session.current_unit_id,
      queue_id: queue ? queue.id : @record.call_session.current_queue_id }
  end

  def call(state)
    return unless state

    valid = state.account_id == @record.account_id && state.qualification_id == @record.id && state.snapshot.is_a?(Hash)
    raise ActiveRecord::RecordNotFound unless valid

    snapshot = state.snapshot
    validate_snapshot!(snapshot)
    origin = snapshot.fetch('origin')

    bindings = JrcContactCenter::AcwFormBindings.new(account: @record.account).references!(snapshot['bindings'], rules: origin.fetch('rules'))
    snapshot.merge('bindings' => bindings).deep_dup
  end
  private

  def validate_snapshot!(snapshot)
    expected = @record.attributes.slice('account_id', 'account_user_id').merge('qualification_id' => @record.id)
    origin = snapshot['origin']
    valid = snapshot.keys.sort == %w[bindings origin reason_codes version] && snapshot['version'] == 1 &&
            origin.is_a?(Hash) && origin.slice(*expected.keys) == expected
    raise JrcContactCenter::OperationError, 'invalid_qualification_form_context' unless valid

    validate_reason_codes!(snapshot, origin)

  end
  def validate_reason_codes!(snapshot, origin)
    expected_reasons = (LEGACY_REASON_CODES_V1 + origin.fetch('rules').pluck('reason_code')).uniq.sort
    valid = snapshot['reason_codes'].is_a?(Array) && snapshot['reason_codes'].all? { |code| code.is_a?(String) && code.length <= 100 }
    raise JrcContactCenter::OperationError, 'invalid_qualification_form_context' unless valid && snapshot['reason_codes'] == expected_reasons

  end

end
