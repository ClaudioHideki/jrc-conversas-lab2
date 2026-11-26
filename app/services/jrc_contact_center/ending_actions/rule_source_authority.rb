# frozen_string_literal: true

# Source restriction for a per-rule configurator, in addition to native configure
# permission and each destination's own policy. It never authorizes the global
# ACW writer or derives a grant from IDs stored in an old private template.
class JrcContactCenter::EndingActions::RuleSourceAuthority
  def initialize(account:, member:)
    @account = account
    @member = account.account_users.find_by!(id: member.id, user_id: member.user_id)
  end

  def call(rule)
    organization = JrcContactCenter::OrganizationalScope.new(account: @account, account_user: @member)
    return rule unless organization.restricted?

    organization.authorize_links!(rule.fetch('scope').slice('issuer_company_id', 'business_unit_id'))
    access = JrcContactCenter::AccessScope.new(user_context: { account: @account, account_user: @member, user: @member.user })
    raise ActiveRecord::RecordNotFound unless access.queues.exists?(id: rule.fetch('queue_id'))

    rule
  end
end
