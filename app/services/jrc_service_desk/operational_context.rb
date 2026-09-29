# frozen_string_literal: true

# Refresh the native authenticated identity for each command/policy evaluation.
# This is not a login mechanism. Never accept this context from request parameters.
class JrcServiceDesk::OperationalContext < JrcServiceDesk::AccessContext
  def initialize(native_context)
    refreshed = refresh_identity(native_context)
    super(refreshed)
  end

  def to_h
    { account: account, user: user, account_user: account_user }
  end

  def native_operator?
    capability?(:module_view)
  end

  def administrator?
    available? && !custom_role_present? && account_user.role == 'administrator'
  end

  def unit_scope
    return JrcServiceDesk::Unit.none unless available?

    granted = JrcServiceDesk::UnitMembership.where(account_id: account.id, account_user_id: account_user.id, active: true).select(:unit_id)
    JrcServiceDesk::Unit.where(account_id: account.id, active: true, id: granted)
      .joins(:operator_company)
      .where(jrc_service_desk_operator_companies: { account_id: account.id, active: true })
  end

  def view_unit_scope
    return unit_scope unless administrator?

    JrcServiceDesk::Unit.where(account_id: account.id, active: true).joins(:operator_company)
      .where(jrc_service_desk_operator_companies: { account_id: account.id, active: true })
  end

  def active_memberships
    return JrcServiceDesk::UnitMembership.none unless available?

    JrcServiceDesk::UnitMembership.where(account_id: account.id, account_user_id: account_user.id, active: true,
                                          unit_id: unit_scope.select(:id))
  end

  def unit_allowed?(unit)
    unit && record_in_account?(unit) && unit_scope.exists?(id: unit.id)
  end

  def native_team_ids
    return Team.none.select(:id) unless available?

    Team.where(account_id: account.id, id: TeamMember.where(user_id: user.id).select(:team_id)).select(:id)
  end

  def capability?(key)
    available? && capability_set.allowed?(key)
  end

  def effective_capabilities
    available? ? capability_set.effective : []
  end

  private

  def capability_set
    return JrcServiceDesk::Capabilities.new unless available?
    if custom_role_present?
      # Do not accept a foreign/dangling native role or downgrade it to a default role.
      return JrcServiceDesk::Capabilities.new unless account_user.respond_to?(:custom_role)
      role = account_user.custom_role
      return JrcServiceDesk::Capabilities.new unless role && role.persisted? && role.id == account_user.custom_role_id && role.account_id == account.id
      return JrcServiceDesk::Capabilities.new unless account_user.permissions.include?('custom_role')

      JrcServiceDesk::Capabilities.new(custom: true, permissions: role.permissions)
    else
      native = Array(account_user.permissions)
      return JrcServiceDesk::Capabilities.new unless native.include?(account_user.role)

      JrcServiceDesk::Capabilities.new(native_role: account_user.role)
    end
  end

  def refresh_identity(context)
    empty = { account: nil, user: nil, account_user: nil }
    return empty unless context.is_a?(Hash)

    a, u, au = context.values_at(:account, :user, :account_user)
    return empty unless a.is_a?(::Account) && u.is_a?(::User) && au.is_a?(::AccountUser)
    return empty unless a.persisted? && u.persisted? && au.persisted?
    return empty unless au.account_id == a.id && au.user_id == u.id

    fresh_account = ::Account.find_by(id: a.id)
    fresh_user = ::User.find_by(id: u.id)
    fresh_membership = ::AccountUser.find_by(id: au.id, account_id: a.id, user_id: u.id)
    { account: fresh_account, user: fresh_user, account_user: fresh_membership }
  end

  def custom_role_present?
    account_user.respond_to?(:custom_role_id) && !account_user.custom_role_id.nil?
  end
end
