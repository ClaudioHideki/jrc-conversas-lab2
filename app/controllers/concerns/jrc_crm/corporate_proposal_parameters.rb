module JrcCrm::CorporateProposalParameters
  def creation_options
    boundary = JrcCrm::OrganizationalVisibility.new(account: crm_scope, user: Current.user,
                                                    relation: JrcCrm::Proposal.where(account_id: crm_scope.id), include_company: false)
    units = crm_scope.jrc_crm_business_units.where(active: true)
    allowed_ids = boundary.allowed_business_unit_ids
    units = units.where(id: allowed_ids) unless allowed_ids.nil?
    render json: { business_units: units.includes(:operating_company).order(:name).map do |unit|
      {
        id: unit.id, name: [unit.operating_company&.name,
                            unit.name].compact.join(' / '), company_id: unit.company_id
      }
    end,
                   unit_required: !allowed_ids.nil? }
  end

  private

  def authorize_operating_unit!(unit)
    boundary = JrcCrm::OrganizationalVisibility.new(account: crm_scope, user: Current.user,
                                                    relation: JrcCrm::Proposal.where(account_id: crm_scope.id), include_company: false)
    return if boundary.allowed_business_unit_ids.nil?
    raise Pundit::NotAuthorizedError unless unit && boundary.allowed_business_unit_ids.include?(unit.id)
  end

  def corporate_proposal_attributes
    proposal_params.to_h.symbolize_keys.merge(JrcCrm::CorporateIssuer.attributes(@proposal.business_unit))
  end

  def build_corporate_proposal(deal, company, contact, unit, attributes)
    items = params.permit(items: [:product_id, :quantity, :unit_price_cents, :discount_cents,
                                  { commercial_gratuity: [:type, :reason] }])[:items] || []
    JrcCrm::ProposalBuilderService.new(deal: deal, account: crm_scope, company: company, contact: contact,
                                       business_unit: unit, attributes: attributes, items: items, actor: Current.user).call
  end
end
