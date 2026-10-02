class JrcCrm::LeadConversionService
  def initialize(lead:, account:, actor:, params:)
    @lead = lead
    @account = account
    @actor = actor
    @params = params.to_h.with_indifferent_access
  end

  def call
    existing = existing_deal
    return success(existing, false) if existing
    return failure('Somente leads qualificados podem ser convertidos.') unless @lead.status_qualified?

    ActiveRecord::Base.transaction do
      @lead.with_lock do
        existing = existing_deal
        if existing
          success(existing, false)
        else
          contact = find_or_create_contact
          company = find_or_create_company
          if @account.feature_enabled?('jrc_customer_master') && company
            if contact.company_id.present? && contact.company_id != company[:id]
              raise JrcCustomers::LegacyCompanyMapper::Conflict, 'Contact is linked to another company; review it before conversion'
            end
            contact.update!(company_id: company[:id]) if contact.company_id.nil?
            @lead.company_id = company[:id]
          end
          deal = create_deal(contact, company)
          attach_product(deal)
          @lead.update!(status: 'converted', converted_at: Time.current, contact: contact)
          log_conversion(deal, contact, company)
          success(deal, true, contact, company&.dig(:record))
        end
      end
    end
  rescue ActiveRecord::RecordNotUnique
    existing = @account.jrc_crm_deals.find_by(conversion_key: conversion_key)
    existing ? success(existing, false) : failure('Identificador duplicado; selecione o cadastro existente e tente novamente.')
  rescue StandardError => e
    failure(e.message)
  end

  private

  def existing_deal
    @account.jrc_crm_deals.find_by(lead_id: @lead.id) || @account.jrc_crm_deals.find_by(conversion_key: conversion_key)
  end

  def conversion_key
    "lead:#{@lead.id}"
  end

  def find_or_create_contact
    return JrcCustomers::LeadContactLinker.new(account: @account).call(@lead) if @account.feature_enabled?('jrc_customer_master')
    return @account.contacts.find(@lead.contact_id) if @lead.contact_id.present?

    contact = @account.contacts.find_by(email: @lead.email) if @lead.email.present?
    contact ||= @account.contacts.find_by(phone_number: @lead.phone) if @lead.phone.present?

    phone = @lead.phone.to_s.strip

    if phone.present? && !phone.start_with?('+')
      digits = phone.gsub(/\D/, '')
      phone = '+55' + digits
    end

    contact || @account.contacts.create!(
      name: @lead.name,
      email: @lead.email,
      phone_number: phone
    )
  end

  def find_or_create_company
    if @account.feature_enabled?('jrc_customer_master')
      id = @params[:company_id].presence || @lead.company_id || @lead.contact&.company_id
      if id.present?
        company = @account.master_companies.find(id)
        return { type: :master_company, record: company, id: company.id }
      end
      if @params[:company_name].present? || @lead.company_name.present?
        raise JrcCustomers::LegacyCompanyMapper::Conflict, 'Select company_id from the master directory before converting this lead'
      end
      return nil
    end
    name = @params[:company_name].presence || @lead.company_name
    return if name.blank?

    JrcCrm::CompanyAdapter.find_or_create(account: @account, name: name)
  end

  def create_deal(contact, company)
    pipeline = selected_pipeline
    stage = selected_stage(pipeline)
    raise ActiveRecord::RecordNotFound, 'Nenhuma etapa ativa disponÃ­vel' unless stage

    @account.jrc_crm_deals.create!(
      title: @params[:deal_title].presence || "NegÃ³cio - #{@lead.name}", pipeline: pipeline, stage: stage,
      owner: selected_owner, team_id: @params[:team_id].presence || @lead.team_id, contact: contact,
      organization_id: company&.dig(:type) == :crm_organization ? company[:id] : nil,
      company_id: [:enterprise_company, :master_company].include?(company&.dig(:type)) ? company[:id] : nil,
      lead: @lead, conversion_key: conversion_key, value_cents: @params[:value_cents].to_i,
      probability: @params[:probability].presence || stage.probability, expected_close_at: @params[:expected_close_at],
      description: @params[:notes].presence || @lead.notes, status: 'open', source: @lead.source,
      product_name: @params[:product_name].presence || @lead.custom_attributes&.dig('product_interest'),
      custom_attributes: { source_conversation_id: @lead.conversation_id }.compact
    ).tap { |deal| deal.link_conversation!(@lead.conversation, @actor) if @lead.conversation }
  end

  def selected_pipeline
    return @account.jrc_crm_pipelines.find(@params[:pipeline_id]) if @params[:pipeline_id].present?

    JrcCrm::DefaultPipelineService.new(@account).perform
  end

  def selected_stage(pipeline)
    return pipeline.stages.find(@params[:stage_id]) if @params[:stage_id].present?

    pipeline.stages.active.order(:position).first
  end

  def selected_owner
    return @lead.owner unless @params[:owner_id].present?

    @account.users.find(@params[:owner_id])
  end

  def attach_product(deal)
    return if @params[:product_id].blank?

    product = @account.jrc_crm_products.active.find(@params[:product_id])
    deal.deal_products.create!(product: product, quantity: 1, unit_price_cents: product.unit_price_cents,
                               discount_cents: 0)
  end

  def log_conversion(deal, contact, company)
    JrcCrm::AuditLoggerService.new(
      account: @account, event_type: 'lead_converted', actor: @actor, resource: @lead,
      from_value: 'qualified', to_value: 'converted',
      metadata: { deal_id: deal.id, contact_id: contact.id, company_id: company&.dig(:id) }
    ).call
  end

  def success(deal, created, contact = nil, company = nil)
    { success: true, created: created, deal: deal, contact: contact || deal.contact, company: company }
  end

  def failure(message)
    { success: false, error: message }
  end
end


