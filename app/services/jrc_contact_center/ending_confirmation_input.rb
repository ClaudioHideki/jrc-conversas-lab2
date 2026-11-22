# frozen_string_literal: true

require 'openssl'

# Private idempotency binding; raw answers and notes never enter the confirmation ledger.
class JrcContactCenter::EndingConfirmationInput
  attr_reader :attributes, :expected_revision, :key

  def initialize(attributes:, expected_revision:, request_key:)
    allowed = JrcContactCenter::QualificationDraft::FIELDS + [JrcContactCenter::QualificationForms::KEY]
    @attributes = JrcServiceDesk::Input.attributes(attributes, allowed).symbolize_keys
    @key = JrcServiceDesk::Input.request_key(request_key)
    @expected_revision = expected_revision
    reason = @attributes[:reason_code]
    valid = reason.is_a?(String) && reason.present? && reason.length <= 100 && reason.exclude?("\0")
    raise JrcContactCenter::OperationError, 'invalid_ending_confirmation' unless valid
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_confirmation'
  end

  def digest(record)
    values = [record.account_id, record.account_user_id, record.id, expected_revision, attributes]
    normalized = JrcServiceDesk::CanonicalJson.normalize(values)
    secret = Rails.application.key_generator.generate_key('jrc_cc_ending_confirmation_input_v1')
    OpenSSL::HMAC.hexdigest('SHA256', secret, JSON.generate(normalized))
  end
end
