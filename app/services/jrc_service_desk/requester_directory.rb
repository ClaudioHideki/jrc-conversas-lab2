# frozen_string_literal: true

# Contacts remain the canonical people registry. Imported organization Contacts
# have an explicit entity marker and must not become ticket requesters.
class JrcServiceDesk::RequesterDirectory
  def initialize(context)
    @context = context
  end

  def scope(company_id: nil, query: nil)
    Pundit.authorize(@context.to_h, Contact, :index?)
    records = Contact.where(account_id: @context.account.id)
      .where("COALESCE(contacts.additional_attributes->>'entity_type', '') <> 'company'")
    if company_id
      company = company!(company_id)
      records = records.where(company_id: company.id)
    end
    term = query.to_s.strip
    return records if term.empty?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    matched = records.where('contacts.name ILIKE :q OR contacts.email ILIKE :q OR contacts.phone_number ILIKE :q', q: pattern)
    digits = term.gsub(/\D/, '')
    if term.match?(/\A[+0-9().\s\/-]+\z/) && digits.length >= 4
      matched = matched.or(records.where("regexp_replace(COALESCE(contacts.phone_number, ''), '[^0-9]', '', 'g') LIKE ?", "%#{digits}%"))
    end
    matched
  end

  def validate!(contact, company_id: nil)
    raise Pundit::NotAuthorizedError unless contact.account_id == @context.account.id
    Pundit.authorize(@context.to_h, contact, :show?)
    if contact.additional_attributes['entity_type'] == 'company'
      raise JrcServiceDesk::RequestValidationError, 'requester_is_company'
    end
    return unless company_id

    company = company!(company_id)
    if contact.company_id != company.id
      raise JrcServiceDesk::RequestValidationError, 'requester_company_mismatch'
    end
  end

  private

  def company!(id)
    raise Pundit::NotAuthorizedError unless @context.capability?(:customers_view)
    Pundit.authorize(@context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
    JrcCrm::CorporateCoverage.new(account: @context.account, user: @context.user)
      .companies(JrcCustomers::Company.where(account_id: @context.account.id)).find(JrcServiceDesk::Input.id(id))
  end
end
