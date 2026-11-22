# frozen_string_literal: true

# One native draft transaction and an immutable explicit confirmation. Never completes ACW or calls a provider.
class JrcContactCenter::ConfirmEndingReason
  def initialize(account:, member:)
    @account = Account.find(account.id)
    @member = @account.account_users.find(member.id)
  end

  def call(record, **)
    input = JrcContactCenter::EndingConfirmationInput.new(**)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      record = JrcContactCenter::Qualification.where(account: @account, account_user: @member).lock.find(record.id)
      authorize!(record)
      existing = previous_request(input)
      if existing
        replay(existing, record, input)
      else
        require_pending!(record)
        confirm!(record, input)
      end
    end
  end

  private

  def authorize!(record)
    context = { account: @account, account_user: @member, user: @member.user }
    allowed = @member.user.reload.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?
    raise Pundit::NotAuthorizedError unless allowed
    raise JrcContactCenter::OperationError, 'ending_confirmation_unavailable' unless record.call_session_id

    JrcContactCenter::AccessScope.new(user_context: context).call_sessions.find(record.call_session_id)
    @policy = JrcContactCenter::EndingReasonPolicy.new(record)
    raise JrcContactCenter::OperationError, 'ending_confirmation_unavailable' unless @policy.private_payload['ending_reason_context']
  end

  def previous_request(input)
    JrcContactCenter::EndingReasonConfirmation.find_by(account: @account, actor_account_user_id: @member.id, request_key: input.key)
  end

  def replay(previous, record, input)
    valid = previous.source_qualification_id == record.id && previous.input_digest == input.digest(record)
    raise JrcContactCenter::OperationError.new('ending_confirmation_content_conflict', status: :conflict) unless valid

    record
  end

  def require_pending!(record)
    raise JrcContactCenter::OperationError.new('qualification_already_completed', status: :conflict) if record.completed_at
    return unless JrcContactCenter::EndingConfirmationState.find(record)

    raise JrcContactCenter::OperationError.new('ending_reason_already_confirmed', status: :conflict)
  end

  def confirm!(record, input)
    raise JrcContactCenter::OperationError, 'registered_ending_reason_required' unless @policy.registered?(input.attributes.fetch(:reason_code))

    digest = input.digest(record)
    draft = JrcContactCenter::QualificationDraft.new(account: @account, member: @member)
    draft.save!(record, input.attributes, expected_revision: input.expected_revision)
    JrcContactCenter::EndingReasonConfirmation.create!(account: @account, qualification: record, request_key: input.key,
                                                       reason_code: record.reload.reason_code, input_digest: digest)
    record
  end
end
