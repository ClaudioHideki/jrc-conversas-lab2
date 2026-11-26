# frozen_string_literal: true

# A capability hint for the current reader only. Both selected commands perform
# the same checks again in their own original-agent transaction before enqueue.
class JrcContactCenter::EndingActions::DestinationOperationAvailability
  def initialize(account:, member:, attempt:)
    @account = account
    @member = member
    @attempt = attempt
  end

  def call
    outcome = @attempt.outcome
    return unavailable if outcome&.outcome == 'succeeded'

    origin = JrcContactCenter::EndingActionOrigin.where(account: @account).find(@attempt.origin_id)
    JrcContactCenter::EndingActions::SelectedDestinationAuthority.new(
      account: @account, member: @member, origin: origin, attempt: @attempt
    ).call
    { can_resume_pending: outcome.nil?, can_retry_selected: outcome && %w[failed blocked].include?(outcome.outcome) ? true : false }
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, JrcContactCenter::OperationError
    unavailable
  end

  private

  def unavailable
    { can_resume_pending: false, can_retry_selected: false }
  end
end
