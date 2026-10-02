# frozen_string_literal: true

# Projection of native customer data, never an operator-company adapter or contact creator.
class JrcServiceDesk::CustomerContextService
  def initialize(user_context:, ticket:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    @ticket = ticket
  end

  def call
    Pundit.authorize(@context.to_h, @ticket, :view_customer?)
    contact = Contact.where(account_id: @context.account.id).find(@ticket.requester_id)
    Pundit.authorize(@context.to_h, contact, :show?)
    company, state = if @context.account.feature_enabled?('jrc_customer_master')
                       master_company(contact)
                     else
                       native_company(contact)
                     end
    { contract_version: 1, account_id: @context.account.id.to_s, unit_id: @ticket.unit_id.to_s,
      ticket_id: @ticket.id.to_s, contact: project(contact), company: company && project(company), company_state: state }
  end

  private

  def project(record)
    { id: record.id.to_s, account_id: record.account_id.to_s, name: record.name.to_s }
  end

  def master_company(contact)
    Pundit.authorize(@context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
    company_id = @ticket.company_id || contact.company_id
    return [nil, 'not_linked'] unless company_id

    [JrcCustomers::Company.where(account_id: @context.account.id).find(company_id), 'available']
  end

  def native_company(contact)
    return [nil, 'not_available'] unless contact.respond_to?(:company_id) && contact.respond_to?(:company)
    return [nil, 'not_linked'] if contact.company_id.nil?

    # The association type is taken from the installed native model, never from input.
    association = contact.class.reflect_on_association(:company)
    return [nil, 'not_available'] unless association
    company = association.klass.where(account_id: @context.account.id).find(contact.company_id)
    Pundit.authorize(@context.to_h, company, :show?)
    [company, 'available']
  end
end
