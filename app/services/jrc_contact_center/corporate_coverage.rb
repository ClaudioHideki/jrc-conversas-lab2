# frozen_string_literal: true

# Retains native coverage rules and direct sources; only Call Center team origins are projected.
class JrcContactCenter::CorporateCoverage < JrcCrm::CorporateCoverage
  def initialize(account:, user:, team_membership_projection: nil, team_activity_preview: {})
    projection = JrcContactCenter::TeamSourceProjection.new(
      account: account, membership: team_membership_projection, activity: team_activity_preview
    )
    super(account: account, user: user, team_membership_projection: projection)
  end
end
