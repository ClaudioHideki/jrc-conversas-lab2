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
    signature.concat(private_components(record)) if include_forms
    Digest::SHA256.hexdigest(signature.to_json)
  end

  def self.check!(record, expected)
    JrcContactCenter::ConfigurationRevision.check_token!(token(record), expected)
  end

  def self.private_components(record)
    forms = JrcContactCenter::QualificationForms.new(record).revision_component
    ending = JrcContactCenter::EndingReasonPolicy.new(record).private_payload
    confirmation = JrcContactCenter::EndingConfirmationState.revision_component(record)
    [forms, (ending if ending.any?), confirmation].compact
  end
  private_class_method :private_components
end
