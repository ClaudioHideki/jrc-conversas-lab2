# frozen_string_literal: true

class JrcContactCenter::TeamActivityWithdrawalReview < JrcContactCenter::TeamRosterWithdrawalReview
  PURPOSE = 'jrc_cc_team_source_activity_v1'

  private

  def roster_sha256
    Digest::SHA256.hexdigest([super, @preview.revision].to_json)
  end
end
