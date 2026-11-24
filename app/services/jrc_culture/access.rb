# frozen_string_literal: true

class JrcCulture::Access
  ACCOUNT_SCOPE = 'account'
  ACCOUNT_SCOPE_LABEL = 'Conta inteira'.freeze

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
    JrcCrm::BusinessUnit.where(account: account, id: admin_grants.select(:unit_id))
  end

  def admin_grants
    grants.where(role: 'administrator')
  end

  def admin_unit_ids
    admin_grants.distinct.pluck(:unit_id)
  end

  def admin_scope_id!(value)
    unit_id = value == ACCOUNT_SCOPE ? nil : Integer(value.to_s, 10)
    authorize_admin_scope!(unit_id)
    unit_id
  rescue ArgumentError, TypeError
    raise ActiveRecord::RecordNotFound
  end

  def authorize_admin_scope!(unit_id)
    deny! unless admin_grants.exists?(unit_id: unit_id)
  end

  def admin!
    deny! unless admin_grants.exists?
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
    version_scope.where(id: JrcCulture::Audience.where(unit_id: admin_unit_ids).select(:version_id))
  end

  def manage_version!(version)
    admin_versions.find(version.id)
    deny! unless version.audiences.pluck(:unit_id).difference(admin_unit_ids).empty?
  end

  def employee_directory(unit_id)
    authorize_admin_scope!(unit_id)
    members = account.account_users.joins(:user).includes(:user).order('users.name', :id)
    return members if unit_id.nil?

    members.where(id: eligible_members(admin_units.find(unit_id)))
  end

  def eligible_member!(unit_id, member_id)
    member = employee_directory(unit_id).find(member_id)
    deny! unless member.user.active_for_authentication?
    member
  end

  def deny!
    raise Pundit::NotAuthorizedError
  end

  private

  def eligible_members(unit)
    scopes = JrcCrm::UserBusinessUnit.active.structure_managed.where(account: account)
    scoped = scopes.where(scope: 'GROUP')
                   .or(scopes.where(scope: 'COMPANY', company_id: unit.company_id))
                   .or(scopes.where(scope: 'BUSINESS_UNIT', business_unit_id: unit.id))
    account.account_users.where(user_id: scoped.select(:user_id)).select(:id)
  end
end
