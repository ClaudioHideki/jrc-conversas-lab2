# Native CRM mutation for the existing Relationship workflow. All writes stay
# inside the same record lock and current customer/CRM authorization boundary.
class JrcRelationship::CommercialOpportunity
  def initialize(context)
    @context = context
  end

  def call(record, pipeline_id:, stage_id:, contact_id: nil)
    assignment = @context.assignment(record.assignment_id, write: true)
    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)

    record.with_lock do
      contact = selected_contact(assignment, contact_id)
      existing = existing_deal(record, assignment, contact)
      next existing if existing

      pipeline = @context.account.jrc_crm_pipelines.active.find(pipeline_id)
      stage = pipeline.stages.active.where(is_terminal: false).find(stage_id)
      deal = create_deal(record, assignment, contact, pipeline, stage)
      attach_product!(record, deal)
      record.update!(deal: deal, status: record.is_a?(JrcRelationship::Renewal) ? 'negotiating' : 'converted')
      @context.audit!(record, after: { deal_id: deal.id }, action: 'crm_opportunity_created')
      deal
    end
  end

  private

  def selected_contact(assignment, contact_id)
    identity = contact_id.presence || assignment.contact_id
    raise ArgumentError, 'Select an existing customer contact before creating the opportunity' unless identity

    contact = assignment.customer_context(@context.member).contacts.find(identity)
    JrcOperations::Access.contact!(@context.member, contact.id)
    contact
  end

  def existing_deal(record, assignment, contact)
    return unless record.deal_id

    deal = assignment.customer_context(@context.member).deals.find(record.deal_id)
    raise ArgumentError, 'The opportunity belongs to a different selected contact' unless deal.contact_id == contact.id

    deal
  end

  def create_deal(record, assignment, contact, pipeline, stage)
    JrcCrm::Deal.create!(account: @context.account, pipeline: pipeline, stage: stage, owner: responsible(record, assignment),
                         contact: contact, company: assignment.company, team: assignment.team, title: title(record),
                         value_cents: amount(record), status: 'open', metadata: metadata(record, assignment))
  end

  def responsible(record, assignment)
    owner = record.owner || assignment.owner || @context.user
    @context.assignable_users.find(owner.id)
    owner
  end

  def title(record)
    record.is_a?(JrcRelationship::Renewal) ? "Renovação #{record.contract.contract_number}" : record.title
  end

  def amount(record)
    record.is_a?(JrcRelationship::Renewal) ? record.proposed_mrr_cents.to_i : record.potential_cents
  end

  def metadata(record, assignment)
    { origin: 'relationship', relationship_assignment_id: assignment.id,
      relationship_resource_type: record.class.name, relationship_resource_id: record.id,
      **commercial_fields(record), business_unit_id: assignment.business_unit_id }
  end

  def commercial_fields(record)
    { source_contract_id: record.try(:source_contract_id) || record.try(:contract_id),
      source_product_id: record.try(:source_product_id), product_id: record.try(:product_id) }
  end

  def attach_product!(record, deal)
    return unless record.is_a?(JrcRelationship::ExpansionSignal) && record.product_id

    product = @context.account.jrc_crm_products.find(record.product_id)
    deal.deal_products.create!(product: product, quantity: 1, unit_price_cents: product.unit_price_cents,
                               description_snapshot: product.description)
  end
end
