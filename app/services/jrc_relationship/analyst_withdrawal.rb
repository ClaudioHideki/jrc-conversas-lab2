# Withdraws only CS eligibility. Account membership, native grants, teams and
# historical executors are never deleted or reassigned here.
class JrcRelationship::AnalystWithdrawal
  def initialize(context)
    @authority = JrcRelationship::BatchReviewAuthority.new(account_id: context.account.id, actor_id: context.user.id)
  end

  def call(analyst_id, reason:, snapshot_digest:)
    validate_input!(reason, snapshot_digest)
    AccountUser.transaction do
      @authority.call do |context|
        raise Pundit::NotAuthorizedError unless context.policy.configure? && context.policy.team?

        analyst = context.assignable_users.find(analyst_id)
        raise Pundit::NotAuthorizedError if analyst.id == context.user.id

        member = context.account.account_users.lock('FOR UPDATE NOWAIT').find_by!(user_id: analyst.id)
        next receipt(member) if member.jrc_relationship_withdrawn_at

        verify_review!(context, member, snapshot_digest)
        withdraw!(context, member, reason, snapshot_digest)
        receipt(member)
      end
    end
  end

  private

  def verify_review!(context, member, digest)
    review = JrcRelationship::WithdrawalReadiness.new(context).call(member.user_id)
    unless ActiveSupport::SecurityUtils.secure_compare(digest, review.fetch(:snapshot_digest))
      raise ActiveRecord::StaleObjectError.new(member, 'withdraw')
    end
    return if review.fetch(:counts).values.all?(&:zero?)

    raise ArgumentError, 'Pending responsibilities require effective native handover before withdrawal'
  end

  def withdraw!(context, member, reason, digest)
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    context.audit!(member, action: 'analyst_withdrawn', before: { jrc_relationship_withdrawn_at: nil },
                           after: { scope: 'relationship', withdrawn_at: member.jrc_relationship_withdrawn_at,
                                    reason: reason.strip, snapshot_digest: digest })
  end

  def validate_input!(reason, digest)
    raise ArgumentError, 'A reason of 1 to 4000 characters is required' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)
    raise ArgumentError, 'A current withdrawal review is required' unless digest.is_a?(String) && digest.match?(/\A[a-f0-9]{64}\z/)
  end

  def receipt(member)
    { state: 'withdrawn', scope: 'relationship', analyst_id: member.user_id, withdrawn_at: member.jrc_relationship_withdrawn_at,
      account_membership_preserved: true }
  end
end
