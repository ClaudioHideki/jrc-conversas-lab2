# frozen_string_literal: true

class JrcServiceDesk::TicketCatalogue
  def initialize(ticket, context:)
    @ticket = ticket
    @context = context
  end

  def bind!(values)
    bind_classification!(values)
    bind_contract!(values['contract_id'])
    service = @ticket.service
    validate_access!(service) if service
    bind_snapshot!(service)
    bind_default_assignee!(service)
  end

  def form_fields
    [@ticket.service, @ticket.ticket_type, @ticket.category, @ticket.subcategory].compact.flat_map(&:form_fields)
  end

  private

  def bind_classification!(values)
    @ticket.ticket_type = reference(JrcServiceDesk::TicketType, selected_type_id(values))
    bind_default_category!
    @ticket.subcategory = reference(JrcServiceDesk::Category, values['subcategory_id'])
  end

  def selected_type_id(values)
    type_id = values['ticket_type_id']
    type_id ||= @ticket.service&.default_ticket_type_id if @ticket.new_record? && !values.key?('ticket_type_id')
    type_id
  end

  def bind_default_category!
    return unless @ticket.new_record?

    @ticket.category ||= reference(JrcServiceDesk::Category, @ticket.service&.default_category_id)
  end

  def bind_snapshot!(service)
    fields = form_fields
    definition = JrcServiceDesk::CatalogueFields.new(fields)
    raise ArgumentError, 'Catalogue contains duplicate or unsupported fields' unless definition.valid? && !definition.duplicate_keys?

    @ticket.catalogue_snapshot = { 'form_fields' => fields, 'classification' => classification_snapshot }
    return unless service

    @ticket.catalogue_snapshot.merge!('service_revision' => JrcServiceDesk::ConfigurationResources.revision('services', service),
                                      'service' => JrcServiceDesk::ConfigurationResources.fields('services', service))
  end

  def bind_default_assignee!(service)
    return unless default_assignee_applicable?(service)

    raise Pundit::NotAuthorizedError unless @context.capability?(:tickets_assign)

    member = service.default_assignee_membership
    user_context = JrcServiceDesk::OperationalContext.new(account: service.account, user: member.account_user.user,
                                                          account_user: member.account_user)
    raise Pundit::NotAuthorizedError unless user_context.unit_allowed?(@ticket.unit) && user_context.capability?(:tickets_view)

    @ticket.assignee_membership = member
  end

  def default_assignee_applicable?(service)
    @ticket.new_record? && service&.default_assignee_membership && @ticket.assignee_membership.nil?
  end

  def validate_access!(service)
    company_id = @ticket.company_id || @ticket.requester.company_id
    allowed = JrcServiceDesk::CatalogueAccess.new(service).allowed?(contact: @ticket.requester, company_id: company_id,
                                                                    contract: @ticket.contract)
    raise Pundit::NotAuthorizedError unless allowed
  end

  def classification_snapshot
    { 'ticket_types' => @ticket.ticket_type, 'categories' => @ticket.category, 'subcategory' => @ticket.subcategory }.filter_map do |key, record|
      next unless record

      resource = key == 'subcategory' ? 'categories' : key
      [key, { 'id' => record.id, 'revision' => JrcServiceDesk::ConfigurationResources.revision(resource, record) }]
    end.to_h
  end

  def reference(model, id)
    model.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, active: true).find(JrcServiceDesk::Input.id(id)) if id
  end

  def bind_contract!(id)
    @ticket.contract = nil
    return unless id

    @ticket.contract = JrcServiceDesk::CatalogueContracts.new(@context).scope.find(JrcServiceDesk::Input.id(id))
    return if JrcServiceDesk::CatalogueContracts.belongs_to?(@ticket.contract, @ticket.requester, @ticket.company_id || @ticket.requester.company_id)

    raise Pundit::NotAuthorizedError
  end
end
