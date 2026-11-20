# frozen_string_literal: true

# Shares the native last-agent impact calculation; never changes the shared roster.
class JrcContactCenter::TeamActivityPreview < JrcContactCenter::TeamRosterPreview
  attr_reader :revision

  def initialize(account:, actor:, team:, revision:)
    @account, @actor, @team, @revision = account, actor, account.teams.find(team.id), revision
    @operation = 'deactivate_source'
    @before_ids = @team.team_members.order(:user_id).pluck(:user_id).freeze
    @after_ids = @before_ids
  end

  def call
    raise Pundit::NotAuthorizedError unless @actor

    context = { account: @account, account_user: @actor, user: @actor.user }
    JrcContactCenter::AccessAuthorization.new(context: context).authorize!
    return [] unless @account.feature_enabled?('jrc_contact_center')

    at = Time.current
    previous = JrcContactCenter::ConfiguredQueueEligibility.new(account: @account, at: at)
    proposed = JrcContactCenter::ConfiguredQueueEligibility.new(account: @account, at: at, team_activity_preview: { @team.id => false })
    impacts = affected_queues.filter_map { |queue| queue_impact(queue, previous, proposed) }
    authorize_impacts!(impacts) if impacts.any?
    impacts
  end

  private

  def affected_queues
    members = @account.account_users.where(user_id: @before_ids).select(:id)
    queue_ids = JrcContactCenter::QueueMembership.where(account: @account, account_user_id: members).select(:queue_id)
    JrcContactCenter::Queue.where(account: @account, id: queue_ids).includes(:unit).order(:id)
  end
end
