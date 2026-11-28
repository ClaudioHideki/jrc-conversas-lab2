# frozen_string_literal: true

require 'digest'

# Local configuration intent only. No provider command, recording or deletion.
class JrcContactCenter::RecordingPolicyDraft
  KEY = 'jrc_contact_center_recording_policy_draft_v1'
  FIELDS = %w[mode queue_scope queue_ids notice retention_days].freeze
  MODES = %w[automatic on_demand].freeze
  SCOPES = %w[unit selected_queues].freeze
  MAX_JSON_INTEGER = 9_007_199_254_740_991
  ERROR = 'invalid_recording_policy_draft'

  def self.parse(values)
    new(values).call
  end

  def self.build(unit:, values:)
    parse(values).merge('scope_snapshot' => scope_snapshot(unit))
  end

  def self.scope_snapshot(unit)
    { 'account_id' => unit.account_id.to_s, 'unit_id' => unit.id.to_s,
      'issuer_company_id' => unit.settings['issuer_company_id'].presence&.to_s,
      'business_unit_id' => unit.settings['business_unit_id'].presence&.to_s }
  end

  def self.stored(unit)
    return unless unit.settings.key?(KEY)

    value = unit.settings.fetch(KEY)
    valid = value.is_a?(Hash) && value['schema_version'] == 1 && value.keys.sort == (FIELDS + %w[schema_version scope_snapshot]).sort
    raise JrcContactCenter::OperationError, ERROR unless valid

    parsed = build(unit: unit, values: value.except('schema_version', 'scope_snapshot'))
    raise JrcContactCenter::OperationError, ERROR unless parsed == value

    parsed
  end

  def self.authorize_queues!(unit:, definition:, scope:)
    scope.where(account_id: unit.account_id, unit_id: unit.id).find(definition.fetch('queue_ids'))
    true
  end

  def self.audit_snapshot(definition)
    definition.except('notice').merge('notice_present' => definition.fetch('notice').present?,
                                      'notice_sha256' => Digest::SHA256.hexdigest(definition.fetch('notice')))
  end

  def initialize(values)
    @values = values
  end

  def call
    invalid! unless @values.is_a?(Hash) && @values.keys.sort == FIELDS.sort
    invalid! unless MODES.include?(@values['mode']) && SCOPES.include?(@values['queue_scope'])

    { 'schema_version' => 1, 'mode' => @values.fetch('mode'), 'queue_scope' => @values.fetch('queue_scope'),
      'queue_ids' => queue_ids, 'notice' => notice, 'retention_days' => retention_days }
  end

  private

  def queue_ids
    raw = @values.fetch('queue_ids')
    invalid! unless raw.is_a?(Array)

    ids = raw.map { |value| JrcServiceDesk::Input.id(value) }.uniq.sort
    valid = @values.fetch('queue_scope') == 'unit' ? ids.empty? : ids.any?
    invalid! unless valid

    ids.map(&:to_s)
  end

  def notice
    value = @values.fetch('notice')
    invalid! unless value.is_a?(String) && value.length <= 1000 && value.bytesize <= 4000

    value
  end

  def retention_days
    value = @values.fetch('retention_days')
    return if value.nil?

    invalid! unless value.is_a?(Integer) && value.positive? && value <= MAX_JSON_INTEGER
    value
  end

  def invalid!
    raise JrcContactCenter::OperationError, ERROR
  end
end
