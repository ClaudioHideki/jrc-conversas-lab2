# frozen_string_literal: true

# Callers retain native own-attendance authorization. The database independently protects the fixed reason.
class JrcContactCenter::EndingConfirmationState
  def self.find(record)
    JrcContactCenter::EndingReasonConfirmation.find_by(account_id: record.account_id, source_qualification_id: record.id)
  end

  def self.validate_reason!(record, reason)
    confirmation = find(record)
    return unless confirmation && confirmation.reason_code != reason

    raise JrcContactCenter::OperationError.new('ending_reason_already_confirmed', status: :conflict)
  end

  def self.private_payload(record)
    row = find(record)
    return {} unless row

    { 'ending_reason_confirmation' => { 'id' => row.id.to_s, 'state' => 'confirmed', 'reason_code' => row.reason_code,
                                        'reason_label' => row.reason_label, 'confirmed_at' => row.created_at.utc.iso8601(6),
                                        'catalogue_id' => row.catalogue_id.to_s, 'integrity_sha256' => row.integrity_sha256,
                                        'completes_acw' => false, 'executes_integrations' => false } }
  end

  def self.revision_component(record)
    row = find(record)
    ['ending_confirmation_v1', row.id, row.integrity_sha256] if row
  end
end
