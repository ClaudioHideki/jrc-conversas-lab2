# frozen_string_literal: true

# Configured local eligibility, not presence or a provider-confirmed distribution result.
class JrcContactCenter::ConfiguredQueueEligibility
  def initialize(account:, team_membership_projection: nil, at: nil)
    @account = account
    @projection = team_membership_projection
    @at = at
  end

  def call(membership)
    at = @at || Time.current
    return false unless membership.account_id == @account.id && membership.active? && membership.role == 'agent'
    return false unless active_membership_window?(membership, at)

    member = @account.account_users.includes(:user).find(membership.account_user_id)
    return false unless authorized_operator?(member)

    queue = JrcContactCenter::Queue.includes(:unit).find_by!(account: @account, id: membership.queue_id)
    organization = JrcContactCenter::OrganizationalScope.new(
      account: @account, account_user: member, team_membership_projection: @projection
    )
    active_queue?(queue, at) && organization.units.exists?(queue.unit_id)
  end

  private

  def authorized_operator?(member)
    member.user.active_for_authentication? && JrcContactCenter::ModulePolicy.new(context(member), :contact_center).operate?
  end

  def context(member)
    values = { account: @account, account_user: member, user: member.user }
    return values unless @projection

    if @projection.includes?(member.user_id)
      grant = JrcContactCenter::AccessGrant.find_by(account: @account, team_id: @projection.team_id)
      values[:cc_extra_team_permissions] = Array(grant&.allowed)
    else
      values[:cc_team_access_preview] = { @projection.team_id => [] }
    end
    values
  end

  def active_queue?(queue, at)
    queue.status == 'active' && queue.unit.status == 'active' &&
      (!queue.active_from || queue.active_from <= at) && (!queue.active_until || queue.active_until > at)
  end

  def active_membership_window?(membership, at)
    (!membership.starts_at || membership.starts_at <= at) && (!membership.ends_at || membership.ends_at > at)
  end
end
