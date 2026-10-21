# frozen_string_literal: true

require 'digest'

class JrcContactCenter::EventIngestor
  REQUIRED_FIELDS = %w[schema_version event_id event_type occurred_at provider].freeze

  Result = Data.define(:record, :created)

  def initialize(account:)
    @account = account
  end

  def call(event, signature_verified: false, received_at: Time.current)
    payload = event.to_h.deep_stringify_keys
    validate_payload!(payload)
    digest = Digest::SHA256.hexdigest(payload.to_json)
    record = find_event(payload)
    return replay_result(record, digest) if record.persisted?

    persist_event(record, payload, digest, signature_verified: signature_verified, received_at: received_at)
  rescue ArgumentError => e
    raise e if e.message.start_with?('missing contact center event fields:') || e.message == 'event replay payload mismatch'

    raise ArgumentError, 'invalid occurred_at in contact center event'
  end

  private

  def validate_payload!(payload)
    missing = REQUIRED_FIELDS.select { |key| payload[key].blank? }
    raise ArgumentError, "missing contact center event fields: #{missing.join(', ')}" if missing.any?
  end

  def find_event(payload)
    JrcContactCenter::EventInbox.find_or_initialize_by(
      account: @account,
      provider: payload.fetch('provider'),
      external_event_id: payload.fetch('event_id')
    )
  end

  def replay_result(record, digest)
    raise ArgumentError, 'event replay payload mismatch' unless ActiveSupport::SecurityUtils.secure_compare(record.payload_digest, digest)

    Result.new(record: record, created: false)
  end

  def persist_event(record, payload, digest, signature_verified:, received_at:)
    record.assign_attributes(
      event_type: payload.fetch('event_type'),
      schema_version: payload.fetch('schema_version'),
      occurred_at: Time.iso8601(payload.fetch('occurred_at').to_s),
      received_at: received_at,
      payload_digest: digest,
      signature_verified: signature_verified,
      payload: payload,
      status: 'pending'
    )
    record.save!
    Result.new(record: record, created: true)
  end
end
