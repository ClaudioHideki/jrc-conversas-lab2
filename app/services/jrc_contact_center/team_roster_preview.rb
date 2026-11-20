# frozen_string_literal: true

# One pure, current/proposed roster comparison. It never calls Team.add/remove_members.
class JrcContactCenter::TeamRosterPreview
  OPERATIONS = %w[create update destroy delete_team].freeze
  attr_reader :before_ids, :after_ids, :team, :operation

  def initialize(account:, actor:, team:, user_ids:, operation:)
    @account = account
    @actor = actor
    @team = account.teams.find(team.id)
    @operation = operation.to_s
    raise ArgumentError, 'Unsupported native roster operation' unless OPERATIONS.include?(@operation)

    authorize_team!
    @before_ids = @team.team_members.pluck(:user_id).sort.freeze
    selected = user_ids.map(&:to_i).uniq
    @after_ids = proposed_ids(selected).sort.freeze
  end

  def call
    authorize_team!
    return [] unless @account.feature_enabled?('jrc_contact_center') && @before_ids != @after_ids

    eligible_users = @account.account_users.where(user_id: @after_ids).pluck(:user_id)
    projection = JrcCrm::TeamMembershipProjection.new(account: @account, team: @team, user_ids: eligible_users)
    at = Time.current
    previous = JrcContactCenter::ConfiguredQueueEligibility.new(account: @account, at: at)
    proposed = JrcContactCenter::ConfiguredQueueEligibility.new(account: @account, at: at, team_membership_projection: projection)
    JrcContactCenter::QueueEligibilityComparison.new(account: @account, actor: @actor, previous: previous, proposed: proposed).call(affected_queues)
  end

  private

  def proposed_ids(selected)
    actual = @account.account_users.where(user_id: selected).pluck(:user_id)
    raise ActiveRecord::RecordNotFound unless actual.sort == selected.sort

    case @operation
    when 'create' then (@before_ids + selected).uniq
    when 'update' then selected
    when 'destroy' then @before_ids - selected
    when 'delete_team' then []
    end
  end

  def authorize_team!
    @account.reload
    @actor.reload
    raise Pundit::NotAuthorizedError unless @actor.account_id == @account.id && @account.active? && @actor.user.reload.active_for_authentication?

    context = { account: @account, account_user: @actor, user: @actor.user }
    permission = @operation == 'delete_team' ? 'destroy' : @operation
    raise Pundit::NotAuthorizedError unless TeamPolicy.new(context, @team).public_send("#{permission}?")
  end

  def affected_queues
    changed = (@before_ids - @after_ids) + (@after_ids - @before_ids)
    members = @account.account_users.where(user_id: changed).select(:id)
    queue_ids = JrcContactCenter::QueueMembership.where(account: @account, account_user_id: members).select(:queue_id)
    JrcContactCenter::Queue.where(account: @account, id: queue_ids).includes(:unit).order(:id)
  end
end
