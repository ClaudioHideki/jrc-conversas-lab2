# frozen_string_literal: true

# Shared current/proposed local eligibility and manager authority, not provider presence.
class JrcContactCenter::QueueEligibilityComparison
  def initialize(account:, actor:, previous:, proposed:)
    @account = account
    @actor = actor
    @previous = previous
    @proposed = proposed
  end

  def call(queues)
    impacts = queues.filter_map { |queue| queue_impact(queue) }
    authorize_impacts!(impacts) if impacts.any?
    impacts
  end

  private

  def queue_impact(queue)
    memberships = queue.memberships.where(account: @account).order(:id).to_a
    before = memberships.filter_map { |row| row.account_user_id if @previous.call(row) }.uniq.sort
    after = memberships.filter_map { |row| row.account_user_id if @proposed.call(row) }.uniq.sort
    return unless before.any? && after.empty?

    { queue: queue, before_ids: before, after_ids: after,
      queue_revision: JrcContactCenter::ConfigurationRevision.token(queue),
      unit_revision: JrcContactCenter::ConfigurationRevision.token(queue.unit) }
  end

  def authorize_impacts!(impacts)
    context = { account: @account, account_user: @actor, user: @actor.user }
    access = JrcContactCenter::AccessScope.new(user_context: context)
    raise Pundit::NotAuthorizedError unless access.policy.configure?

    permitted = access.queues.pluck(:id)
    raise Pundit::NotAuthorizedError unless impacts.all? { |row| permitted.include?(row.fetch(:queue).id) }
  end
end
