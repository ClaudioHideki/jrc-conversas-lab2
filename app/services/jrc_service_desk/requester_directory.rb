# frozen_string_literal: true

# Contacts remain the canonical people registry. Imported organization Contacts
# have an explicit entity marker and must not become ticket requesters.
class JrcServiceDesk::RequesterDirectory
  def initialize(context)
    @context = context
  end

  def scope(company_id: nil, query: nil)
    Pundit.authorize(@context.to_h, Contact, :index?)
    records = JrcCustomers::RequesterIdentity.people(visible_contacts)
    if company_id
      company = company!(company_id)
      records = records.where(company_id: company.id)
    end
    term = query.to_s.strip
    return records if term.empty?

    JrcCustomers::ContactQuery.new(account: @context.account, scope: records, query: term, include_company: false).call
  end

  def validate!(contact, company_id: nil)
    raise Pundit::NotAuthorizedError unless contact.account_id == @context.account.id
    Pundit.authorize(@context.to_h, contact, :show?)
    raise ActiveRecord::RecordNotFound unless visible_contacts.exists?(id: contact.id)
    reason = JrcCustomers::RequesterIdentity.reason(contact)
    if reason
      raise JrcServiceDesk::RequestValidationError, reason == 'organization' ? 'requester_is_company' : 'requester_review_required'
    end
    return unless company_id

    company = company!(company_id)
    if contact.company_id != company.id
      raise JrcServiceDesk::RequestValidationError, 'requester_company_mismatch'
    end
  end

  def visible_contacts
    Pundit.authorize(@context.to_h, Contact, :index?)
    companies = JrcCrm::CorporateCoverage.new(account: @context.account, user: @context.user)
      .companies(@context.account.master_companies).select(:id)
    @context.account.contacts.where(company_id: nil).or(@context.account.contacts.where(company_id: companies))
  end

  def company!(id)
    raise Pundit::NotAuthorizedError unless @context.capability?(:customers_view)
    Pundit.authorize(@context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
    JrcCrm::CorporateCoverage.new(account: @context.account, user: @context.user)
      .companies(JrcCustomers::Company.where(account_id: @context.account.id)).find(JrcServiceDesk::Input.id(id))
  end
end
