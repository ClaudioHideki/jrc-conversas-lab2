module JrcCrm
  class ProposalBuilderService
    DEFAULT_COMMERCIAL_NOTES = <<~TEXT.strip.freeze
      Valores em reais. Condições sujeitas a validação comercial e técnica.
      Consumos variáveis, excedentes, APIs, mensagens e serviços não descritos nos itens serão faturados conforme utilização e contratação aplicável.
    TEXT

    DEFAULT_NEXT_STEPS = <<~TEXT.strip.freeze
      1. Aprovação do escopo e das condições comerciais
      2. Alinhamento técnico e confirmação dos dados de implantação
      3. Configuração, testes e homologação
      4. Go-live e acompanhamento inicial da operação
    TEXT

    def initialize(actor:, deal: nil, account: nil, company: nil, contact: nil, business_unit: nil, attributes: {}, items: [])
      @deal = deal
      @actor = actor
      @account = account || deal&.account || company&.account || contact&.account
      @company = company
      @contact = contact
      @business_unit = business_unit
      @business_unit ||= JrcApprovals::CommercialCatalog.business_unit(@deal) if @deal
      @attributes = attributes.to_h.symbolize_keys
      @items = items
    end

    def call
      JrcCrm::CorporateIssuer.authorize!(account: @account, user: @actor, unit: @business_unit)
      ActiveRecord::Base.transaction do
        proposal = JrcCrm::Proposal.create!({
          account_id: @account.id,
          deal_id: @deal&.id,
          company: @company, contact: @contact, business_unit: @business_unit,
          owner_id: @deal&.owner_id || @actor.id,
          title: "Proposta - #{@deal&.title || @company&.name || @contact&.name}",
          status: 'draft',
          solution_description: @deal&.description.presence || default_solution_description,
          implementation_cents: 0,
          monthly_cents: 0,
          valid_until: 15.days.from_now.to_date,
          term_months: 12,
          commercial_notes: DEFAULT_COMMERCIAL_NOTES,
          next_steps: DEFAULT_NEXT_STEPS,
          approval_status: 'not_required',
          commercial_approval_status: 'not_required',
          financial_approval_status: 'not_required',
          technical_approval_status: 'not_required'
        }.merge(@attributes).merge(JrcCrm::CorporateIssuer.attributes(@business_unit)).merge(down_payment_cents: 0))

        create_items!(proposal)

        proposal.update!(down_payment_cents: @attributes[:down_payment_cents]) if @attributes.key?(:down_payment_cents)
        proposal.reload
        proposal.recalculate_totals!

        JrcCrm::ProposalEvent.create!(
          account_id: @account.id,
          proposal_id: proposal.id,
          event_type: 'created',
          user_id: @actor.id,
          metadata: { relationship_origin: if @deal
                                             @deal.metadata.to_h.slice('origin', 'relationship_assignment_id',
                                                                       'relationship_resource_type',
                                                                       'relationship_resource_id', 'source_contract_id',
                                                                       'product_id', 'business_unit_id')
                                           else
                                             {}
                                           end },
          description: @deal ? 'Proposta criada a partir do negócio' : 'Proposta criada diretamente para cliente do Cadastro Mestre'
        )

        proposal.reload
      end
    end

    private

    def create_items!(proposal)
      if @deal
        @deal.deal_products.includes(:product).find_each { |row| create_item_from_deal_product!(proposal, row) }
      else
        @items.each { |values| create_direct_item!(proposal, values) }
      end
    end

    def create_direct_item!(proposal, values)
      item = values.to_h.deep_symbolize_keys
      product = JrcCrm::CorporateIssuer.product!(account: @account, user: @actor, id: item.fetch(:product_id), unit: @business_unit)
      snapshot = JrcCrm::CommercialProductSnapshot.from_product(product, intent: item[:commercial_gratuity])
      proposal.proposal_items.create!(snapshot.merge(item.slice(:quantity, :unit_price_cents, :discount_cents, :commercial_gratuity)).merge(
                                        product: product, name_snapshot: product.name, description_snapshot: product.description
                                      ))
    end

    def create_item_from_deal_product!(proposal, deal_product)
      product = deal_product.product
      JrcCrm::CorporateIssuer.product!(account: @account, user: @actor, id: product.id, unit: @business_unit) if product
      snapshot = JrcCrm::CommercialProductSnapshot.from_product(product, intent: deal_product.commercial_gratuity)
      JrcCrm::ProposalItem.create!(snapshot.merge(
                                     proposal_id: proposal.id,
                                     product_id: product&.id,
                                     name_snapshot: product&.name || deal_product.description_snapshot.presence || 'Item sem nome',
                                     description_snapshot: deal_product.description_snapshot.presence || product&.description,
                                     unit_price_cents: deal_product.unit_price_cents || product&.unit_price_cents || 0,
                                     quantity: deal_product.quantity || 1,
                                     discount_cents: deal_product.discount_cents || 0,
                                     commercial_gratuity: deal_product.commercial_gratuity
                                   ))
    end

    def default_solution_description
      customer_name = @contact&.name.presence || @company&.name || @deal&.contact&.name.presence || @deal&.title
      "Solução comercial JRC preparada para #{customer_name}, reunindo atendimento, relacionamento e operação em um único fluxo."
    end
  end
end
