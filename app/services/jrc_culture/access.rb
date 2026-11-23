# frozen_string_literal: true

class JrcCulture::Access
  attr_reader :account, :user, :member

  def self.accounts(user)
    return Account.none unless user&.active_for_authentication?

    account_ids = JrcCulture::Grant.eligible.where(account_users: { user_id: user.id }).select(:account_id)
    Account.where(id: account_ids, status: :active)
  end

  def initialize(account:, user:)
    @account = account
    @user = user
    @member = account.account_users.find_by(user_id: user.id)
    deny! unless account.active? && member && user.active_for_authentication? && grants.exists?
  end

  def grants
    JrcCulture::Grant.eligible.where(account: account, account_user: member, user_key: user.id)
  end

  def employee_grants
    grants.where(role: 'employee')
  end

  def admin_units
    JrcCrm::BusinessUnit.where(account: account, id: grants.where(role: 'administrator').select(:unit_id))
  end

  def admin!
    deny! unless admin_units.exists?
  end

  def version_scope
    JrcCulture::Version.joins(:manual).where(jrc_culture_manuals: { account_id: account.id })
  end

  def own_participations
    JrcCulture::Participation.where(grant_id: employee_grants.select(:id), version_id: version_scope.select(:id))
  end

  def visible_versions
    assignments = own_participations.confirmed.or(own_participations.where(version_id: version_scope.published.select(:id)))
    version_scope.where(id: assignments.select(:version_id))
  end

  def admin_versions
    admin!
    version_scope.where(id: JrcCulture::Audience.where(unit_id: admin_units.select(:id)).select(:version_id))
  end

  def manage_version!(version)
    admin_versions.find(version.id)
    deny! if version.audiences.where.not(unit_id: admin_units.select(:id)).exists?
  end

  def employee_directory(unit)
    account.account_users.joins(:user).includes(:user).where(id: eligible_members(unit)).order('users.name', :id)
  end

  def eligible_member!(unit, member_id)
    member = employee_directory(unit).find(member_id)
    deny! unless member.user.active_for_authentication?
    member
  end

  def deny!
    raise Pundit::NotAuthorizedError
  end

  private

  def eligible_members(unit)
    admin_units.find(unit.id)
    scopes = JrcCrm::UserBusinessUnit.active.structure_managed.where(account: account)
    scoped = scopes.where(scope: 'GROUP')
                   .or(scopes.where(scope: 'COMPANY', company_id: unit.company_id))
                   .or(scopes.where(scope: 'BUSINESS_UNIT', business_unit_id: unit.id))
    account.account_users.where(user_id: scoped.select(:user_id)).select(:id)
  end
end
