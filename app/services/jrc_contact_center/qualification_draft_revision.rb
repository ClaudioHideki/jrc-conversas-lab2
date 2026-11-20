# frozen_string_literal: true

# A manual-state precondition, never an authorization grant. Clock observations do not invalidate it.
class JrcContactCenter::QualificationDraftRevision
  FIELDS = %w[id account_id account_user_id channel call_session_id conversation_id conversation_cycle started_at completed_at
              reason_code outcome_code notes acw_limit_seconds duration_seconds].freeze

  def self.token(record, include_forms: true)
    values = FIELDS.map do |field|
      value = record.public_send(field)
      value.respond_to?(:iso8601) ? value.utc.iso8601(6) : value
    end
    signature = ['qualification_manual_state_v1', values]
    forms = JrcContactCenter::QualificationForms.new(record).revision_component if include_forms
    signature << forms if forms
    ending = JrcContactCenter::EndingReasonPolicy.new(record).private_payload if include_forms
    signature << ending if ending&.any?
    Digest::SHA256.hexdigest(signature.to_json)
  end

  def self.check!(record, expected)
    JrcContactCenter::ConfigurationRevision.check_token!(token(record), expected)
  end
end
