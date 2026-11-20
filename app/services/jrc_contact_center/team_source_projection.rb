# frozen_string_literal: true

# A read-only Call Center projection; never edits TeamMember or the shared corporate sources.
class JrcContactCenter::TeamSourceProjection
  def initialize(account:, membership: nil, activity: {})
    @account_id = account.id
    @membership = membership
    @activity = activity
  end

  def team_ids(account:, user:, current:)
    raise ActiveRecord::RecordNotFound unless account.id == @account_id

    relation = @membership ? @membership.team_ids(account: account, user: user, current: current) : current
    inactive = JrcContactCenter::TeamState.where(account: account, active: false).where.not(team_id: @activity.keys).select(:team_id)
    excluded = @activity.filter_map { |id, active| id unless active }
    relation.where.not(id: inactive).where.not(id: excluded)
  end
end
