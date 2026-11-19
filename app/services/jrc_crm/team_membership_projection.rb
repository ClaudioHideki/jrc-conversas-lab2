# frozen_string_literal: true

# Trusted, read-only prospective membership. Never construct a grant from request scope IDs.
class JrcCrm::TeamMembershipProjection
  attr_reader :team_id

  def initialize(account:, team:, user_ids:)
    @account_id = account.id
    @team_id = account.teams.find(team.id).id
    @user_ids = user_ids.map(&:to_i).uniq.freeze
    actual = account.account_users.where(user_id: @user_ids).pluck(:user_id)
    raise ActiveRecord::RecordNotFound unless actual.sort == @user_ids.sort
  end

  def includes?(user_id)
    @user_ids.include?(user_id)
  end

  def team_ids(account:, user:, current:)
    raise ActiveRecord::RecordNotFound unless account.id == @account_id

    remaining = current.where.not(id: @team_id)
    return remaining unless includes?(user&.id)

    account.teams.where(id: remaining).or(account.teams.where(id: @team_id)).select(:id)
  end
end
