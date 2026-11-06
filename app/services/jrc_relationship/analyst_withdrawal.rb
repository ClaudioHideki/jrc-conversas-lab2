# Withdraws only CS eligibility. Account membership, native grants, teams and
# historical executors are never deleted or reassigned here.
class JrcRelationship::AnalystWithdrawal
  def initialize(context)
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id)
  end

  def call(analyst_id, reason:, snapshot_digest:)
    validate_input!(reason, snapshot_digest)
    with_member(analyst_id) do |context, member|
      if member.jrc_relationship_withdrawn_at
        verify_retry!(context, member, snapshot_digest)
        next receipt(member)
      end

      verify_review!(context, member, snapshot_digest)
      withdraw!(context, member, reason, snapshot_digest)
      receipt(member)
    end
  end

  def restore(analyst_id, reason:, expected_version:)
    validate_reason!(reason)
    raise ArgumentError, 'A current whole-number eligibility revision is required' unless expected_version.is_a?(Integer) && expected_version >= 0

    with_member(analyst_id) do |context, member|
      raise ActiveRecord::StaleObjectError.new(member, 'restore') unless expected_version == member.jrc_relationship_eligibility_version
      raise ArgumentError, 'Analyst is not withdrawn from Relationship' unless member.jrc_relationship_withdrawn_at
      raise Pundit::NotAuthorizedError unless member.user.active_for_authentication?

      JrcRelationship::WithdrawalReadiness.new(context).call(member.user_id)
      before = { jrc_relationship_withdrawn_at: member.jrc_relationship_withdrawn_at, eligibility_version: expected_version }
      member.update!(jrc_relationship_withdrawn_at: nil, jrc_relationship_eligibility_version: expected_version + 1)
      context.audit!(member, action: 'analyst_withdrawal_reversed', before: before,
                             after: { scope: 'relationship', reason: reason.strip, eligibility_version: member.jrc_relationship_eligibility_version })
      { state: 'withdrawal_reversed', scope: 'relationship', analyst_id: member.user_id,
        eligibility_version: member.jrc_relationship_eligibility_version, native_permissions_required: true }
    end
  end

  private

  def with_member(analyst_id)
    AccountUser.transaction do
      @authority.call do |context|
        raise Pundit::NotAuthorizedError unless context.policy.configure? && context.policy.team?

        analyst = context.assignable_users.find(analyst_id)
        raise Pundit::NotAuthorizedError if analyst.id == context.user.id

        member = context.account.account_users.lock('FOR UPDATE NOWAIT').find_by!(user_id: analyst.id)
        yield context, member
      end
    end
  end

  def verify_retry!(context, member, digest)
    event = JrcCrm::AuditEvent.where(account: context.account).for_resource('AccountUser', member.id)
                              .where("metadata ->> 'action' = ?", 'analyst_withdrawn').order(id: :desc).first
    current = event && event.to_value.fetch('eligibility_version', 0) == member.jrc_relationship_eligibility_version &&
              ActiveSupport::SecurityUtils.secure_compare(event.to_value.fetch('snapshot_digest', ''), digest)
    raise ActiveRecord::StaleObjectError.new(member, 'withdraw') unless current
  end

  def verify_review!(context, member, digest)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(member.user_id)
    unless ActiveSupport::SecurityUtils.secure_compare(digest, review.fetch(:snapshot_digest))
      raise ActiveRecord::StaleObjectError.new(member, 'withdraw')
    end
    return if review.fetch(:counts).values.all?(&:zero?)

    raise ArgumentError, 'Pending responsibilities require effective native handover before withdrawal'
  end

  def withdraw!(context, member, reason, digest)
    member.update!(jrc_relationship_withdrawn_at: Time.current,
                   jrc_relationship_eligibility_version: member.jrc_relationship_eligibility_version + 1)
    context.audit!(member, action: 'analyst_withdrawn', before: { jrc_relationship_withdrawn_at: nil },
                           after: { scope: 'relationship', withdrawn_at: member.jrc_relationship_withdrawn_at,
                                    reason: reason.strip, snapshot_digest: digest, eligibility_version: member.jrc_relationship_eligibility_version })
  end

  def validate_input!(reason, digest)
    validate_reason!(reason)
    raise ArgumentError, 'A current withdrawal review is required' unless digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/)
  end

  def validate_reason!(reason)
    raise ArgumentError, 'A reason of 1 to 4000 characters is required' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)
  end

  def receipt(member)
    { state: 'withdrawn', scope: 'relationship', analyst_id: member.user_id, withdrawn_at: member.jrc_relationship_withdrawn_at,
      account_membership_preserved: true, eligibility_version: member.jrc_relationship_eligibility_version }
  end
end
