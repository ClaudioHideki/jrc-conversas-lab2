# frozen_string_literal: true

# A deletion receipt cannot authorize roster edits, or vice versa. Native deletion consequences stay unchanged.
class JrcContactCenter::TeamDeletionReview < JrcContactCenter::TeamRosterWithdrawalReview
  PURPOSE = 'jrc_cc_team_deletion_v1'

  class Required < JrcContactCenter::OperationError
    attr_reader :review

    def initialize(review)
      @review = review
      super('team_deletion_confirmation_required', status: :conflict)
    end
  end

  private

  def identity
    super.merge('team_revision' => JrcContactCenter::ConfigurationRevision.token(@preview.team))
  end
end
