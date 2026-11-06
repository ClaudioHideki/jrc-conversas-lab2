# Shared subject predicates over native authorized sources. This builds only the
# requested relations, without initializing an aggregate360, timeline or audit.
class JrcCustomers::SubjectSources
  attr_reader :visibility, :contacts

  def initialize(account:, user:, account_user:, company: nil, contact: nil)
    @account = account
    @company = company
    @contact = contact
    @visibility = JrcCustomers::Visibility.new(account: account, user: user, account_user: account_user)
    @visibility.authorize_subject!(company: company, contact: contact)
    @contacts = contact ? account.contacts.where(id: contact.id) : account.contacts.where(company_id: company.id)
  end

  def related(scope, contact_ids = contacts.select(:id))
    return scope.where(contact_id: contact_ids) if @contact

    scope.where(company_id: @company.id).or(scope.where(company_id: nil, contact_id: contact_ids))
  end

  def deals
    @deals ||= related(visibility.crm(@account.jrc_crm_deals))
  end

  def projects
    @projects ||= related(visibility.projects)
  end

  def orders
    @orders ||= begin
      scope = visibility.crm(JrcCrm::SalesOrder.where(account_id: @account.id))
      scope.where(contact_id: contacts.select(:id)).or(scope.where(deal_id: deals.select(:id)))
    end
  end
end
