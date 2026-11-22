# frozen_string_literal: true

# Pending manual answers on the native qualification, using its frozen origin rules.
class JrcContactCenter::QualificationDraft
  FIELDS = %i[reason_code outcome_code notes].freeze
  AUDIT_COMMENT = 'jrc_contact_center_qualification_draft_v1'

  def initialize(account:, member:)
    @account = account
    @member = account.account_users.find(member.id)
  end

  def save!(record, attributes, expected_revision:)
    @account.with_lock do
      record = JrcContactCenter::Qualification.where(account: @account, account_user: @member).lock.find(record.id)
      raise JrcContactCenter::OperationError.new('qualification_already_completed', status: :conflict) if record.completed_at
      raise JrcContactCenter::OperationError.new('qualification_not_started', status: :conflict) unless record.started_at

      lock_current_conversation!(record)
      JrcContactCenter::QualificationDraftRevision.check!(record, expected_revision)
      previous = JrcContactCenter::QualificationDraftRevision.token(record)
      reason = attributes.fetch(:reason_code, record.reason_code)
      JrcContactCenter::EndingConfirmationState.validate_reason!(record, reason)
      JrcContactCenter::EndingReasonPolicy.new(record).validate!(reason, complete: false)
      JrcContactCenter::QualificationForms.new(record).save!(attributes, complete: false)
      record.update!(draft_values(record, attributes))
      audit!(record, previous)
      record
    end
  end

  private

  def lock_current_conversation!(record)
    return unless record.conversation

    record.conversation.lock!
    return if record.conversation_cycle == record.conversation.additional_attributes.fetch('jrc_acw_cycle', 0).to_i

    raise JrcContactCenter::OperationError.new('attendance_cycle_conflict', status: :conflict)
  end

  def draft_values(record, attributes)
    values = record.attributes.symbolize_keys.slice(*FIELDS).merge(attributes.slice(*FIELDS))
    validate_values!(values)
    limit = JrcContactCenter::AcwQualificationPolicy.new(record).draft_limit(values[:reason_code])
    elapsed = [(Time.current - record.started_at).to_i, 0].max
    values.merge(acw_limit_seconds: limit, overdue: elapsed >= limit, exceeded_seconds: [elapsed - limit, 0].max)
  end

  def validate_values!(values)
    valid = values.values.all? { |value| value.nil? || value.is_a?(String) } &&
            values.values_at(:reason_code, :outcome_code).all? { |value| value.nil? || value.length <= 100 }
    raise JrcContactCenter::OperationError, 'invalid_qualification_draft' unless valid
  end

  def audit!(record, previous)
    current = JrcContactCenter::QualificationDraftRevision.token(record)
    return if previous == current

    Audited.audit_class.create!(
      auditable: record, associated: @account, user: @member.user, action: 'update', comment: AUDIT_COMMENT,
      audited_changes: { 'manual_revision' => [previous, current], 'schema_version' => 1 }
    )
  end
end
