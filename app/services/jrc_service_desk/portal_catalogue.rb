# frozen_string_literal: true

class JrcServiceDesk::PortalCatalogue
  def initialize(contact:, service:)
    @contact = contact
    @service = service
  end

  def allowed?
    return false unless configuration_ready? && valid_fields? && customer_allowed?

    @service.allowed_contract_ids.empty? || contracts.any?
  end

  def contracts
    member = @service.portal_execution_membership&.account_user
    return [] unless member

    context = JrcServiceDesk::OperationalContext.new(account: @service.account, user: member.user, account_user: member)
    rows = JrcServiceDesk::CatalogueContracts.new(context).scope.where(status: %w[active expiring], signature_status: 'signed')
    rows = rows.where(id: @service.allowed_contract_ids) if @service.allowed_contract_ids.any?
    rows.includes(:contact, :deal).select do |contract|
      JrcServiceDesk::CatalogueContracts.belongs_to?(contract, @contact, @contact.company_id)
    end
  end

  def form_fields
    [@service, @service.default_ticket_type, @service.default_category].compact.flat_map(&:form_fields)
  end

  private

  def configuration_ready?
    configuration = JrcServiceDesk::ServicePortalConfiguration.new(@service)
    configuration.ready? && configuration.permitted?
  end

  def customer_allowed?
    return false if @service.portal_access_until && @service.portal_access_until <= Time.current

    @service.allowed_company_ids.empty? || @service.allowed_company_ids.include?(@contact.company_id)
  end

  def valid_fields?
    return false unless [@service.default_ticket_type, @service.default_category].compact.all?(&:active?)

    fields = JrcServiceDesk::CatalogueFields.new(form_fields)
    fields.valid? && !fields.duplicate_keys?
  end
end
