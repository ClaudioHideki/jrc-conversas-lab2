# frozen_string_literal: true

# Uses the same commercial visibility as Customer 360; Contract has no separate
# Pundit policy or duplicated customer-company column in the native CRM.
class JrcServiceDesk::CatalogueContracts
  def initialize(context)
    @context = context
  end

  def scope
    JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.account_user)
                            .crm(JrcCrm::Contract.where(account_id: @context.account.id))
  end

  def self.company_id(contract)
    ids = [contract.contact&.company_id, contract.deal&.company_id].compact.uniq
    ids.one? ? ids.first : nil
  end

  def self.belongs_to?(contract, contact, company_id)
    return false unless contract.account_id == contact.account_id
    return true if contract.contact_id == contact.id

    company_id && contact.company_id == company_id && company_id == self.company_id(contract)
  end
end
