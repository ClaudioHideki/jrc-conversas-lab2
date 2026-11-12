# Use the existing directory permission and corporate company coverage for both
# the contact lookup and any protected extension of that contact.
class JrcCustomers::ContactDirectory
  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def scope
    authorize!
    self.class.covered_scope(account: @account, actor: @actor)
  end

  def self.covered_scope(account:, actor:)
    return account.contacts.none unless actor.is_a?(User)

    companies = JrcCrm::CorporateCoverage.new(account: account, user: actor).companies(account.master_companies).select(:id)
    account.contacts.where(company_id: nil).or(account.contacts.where(company_id: companies))
  end

  def find(id)
    scope.find(id)
  end

  def with_locked_contact(id)
    authorize!
    @account.with_lock do
      contact = find(id)
      contact.with_lock do
        find(contact.id)
        yield contact
      end
    end
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless @actor.is_a?(User)

    @account.reload
    @actor.reload
    member = AccountUser.find_by(account_id: @account.id, user_id: @actor.id)
    raise Pundit::NotAuthorizedError unless member && @account.active? && @actor.active_for_authentication?

    context = { account: @account, user: @actor, account_user: member }
    raise Pundit::NotAuthorizedError unless JrcCustomers::DirectoryPolicy.new(context, :directory).access?
  end
end
