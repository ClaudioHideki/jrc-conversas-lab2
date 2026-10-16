module JrcCrm::CorporateStructureParameters
  private

  def company_deactivation_blocked?(company, attrs)
    return false unless attrs.key?(:active) && !ActiveModel::Type::Boolean.new.cast(attrs[:active])

    crm_scope.jrc_crm_business_units.exists?(company_id: company.id, active: true) ||
      crm_scope.jrc_crm_team_scopes.exists?(company_id: company.id, active: true) ||
      crm_scope.jrc_crm_user_business_units.structure_managed.exists?(company_id: company.id, active: true)
  end

  def unit_deactivation_blocked?(unit, attrs)
    return false unless attrs.key?(:active) && !ActiveModel::Type::Boolean.new.cast(attrs[:active])

    crm_scope.jrc_crm_team_scopes.exists?(business_unit_id: unit.id, active: true) ||
      crm_scope.jrc_crm_user_business_units.structure_managed.exists?(business_unit_id: unit.id, active: true)
  end

  def ensure_initial_segment!(attributes)
    initial = { 'Operadora JRC' => 'Telecom', 'GoPure' => 'Comércio / Produtos', 'Construtora JRC' => 'Construção civil' }
    return unless initial[attributes[:name]] == attributes[:segment]

    segment = JrcCustomers::Taxonomy.find_or_initialize_by(account: crm_scope, kind: 'segment', name: attributes[:segment])
    return if segment.persisted?

    segment.save!
    audit!('organizational_segment_created', segment, {}, segment.attributes)
  end

  def settings_params
    params.require(:settings).permit(:group_name, :scope_enforcement_enabled,
                                     approval_authorities: JrcCrm::CorporateProfile::AUTHORITY_PROFILE_FIELDS)
  end

  def company_params
    params.require(:company).permit(:name, :trade_name, :tax_id, :state_registration, :municipal_registration,
                                    :segment, :owner_id, :active, :description,
                                    profile: [*JrcCrm::CorporateProfile::TEXT_FIELDS, *JrcCrm::CorporateProfile::AUTHORITY_FIELDS,
                                              :fiscal_address_id, { responsible_account_user_ids: [] }]).to_h.symbolize_keys
  end

  def corporate_company_attributes(company)
    attrs = company_params
    profile = attrs.delete(:profile)
    attrs[:custom_attributes] = JrcCrm::CorporateProfile.merge!(company: company, account: crm_scope, attributes: profile) if profile
    attrs.merge(relationship_type: 'internal', person_kind: 'organization', economic_group: service.snapshot[:group][:name])
  end

  def authorize_corporate_company!(id)
    raise Pundit::NotAuthorizedError unless JrcCrm::CorporateCoverage.new(account: crm_scope, user: Current.user).company_allowed?(id)
  end

  def business_unit_params
    params.require(:business_unit).permit(:name, :code, :segment, :active, :company_id, settings: {}).to_h.symbolize_keys
  end

  def normalized_business_unit_params
    attrs = business_unit_params
    raise ActiveRecord::RecordNotFound, 'operating company not found' if attrs[:company_id].blank?

    attrs[:company_id] = internal_companies.find(attrs[:company_id]).id
    authorize_corporate_company!(attrs[:company_id])
    settings = attrs[:settings]
    if settings.is_a?(Hash) && settings['service_desk_unit_id'].present?
      native = JrcServiceDesk::OperationalContext.new(pundit_user)
      linked = native.unit_scope.find(settings['service_desk_unit_id'])
      settings['service_desk_unit_id'] = linked.id.to_s
    end
    attrs
  end
end
