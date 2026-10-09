# frozen_string_literal: true

# Commercial IDs are canonical references. An empty restriction preserves the
# existing open catalogue; a configured restriction never selects a customer.
class JrcServiceDesk::CatalogueAccess
  def initialize(service)
    @service = service
  end

  def allowed?(contact:, company_id:, contract: nil)
    return false unless customer_allowed?(contact, company_id)
    return false unless ids_allowed?(@service.allowed_contract_ids, contract&.id)
    return true unless contract

    eligible_contract?(contract) && JrcServiceDesk::CatalogueContracts.belongs_to?(contract, contact, company_id)
  end

  def validate_configuration!(context)
    @service.allowed_company_ids.each do |id|
      company = JrcCustomers::Company.where(account_id: @service.account_id).find(id)
      Pundit.authorize(context.to_h, :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
      raise Pundit::NotAuthorizedError unless context.capability?(:customers_view) && company.account_id == context.account.id
    end
    @service.allowed_contract_ids.each do |id|
      JrcServiceDesk::CatalogueContracts.new(context).scope.find(id)
    end
  end

  private

  def customer_allowed?(contact, company_id)
    return false unless contact.account_id == @service.account_id
    return false if @service.allowed_company_ids.any? && contact.company_id != company_id

    ids_allowed?(@service.allowed_company_ids, company_id)
  end

  def eligible_contract?(contract)
    contract.account_id == @service.account_id && contract.signature_status == 'signed' && (contract.active? || contract.expiring?)
  end

  def ids_allowed?(ids, value)
    ids.empty? || (value && ids.include?(value))
  end
end
