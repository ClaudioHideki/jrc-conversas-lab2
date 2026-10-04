module JrcCrm
  class ProposalToOrderService
    attr_reader :created

    def initialize(proposal:, actor:)
      @proposal, @actor = proposal, actor
      @created = false
    end

    def call
      # All entry points (top-level proposal_id, wizard and proposal action) use
      # this source-row lock. No paid/accepted values are recalculated in place.
      @proposal.with_lock do
        raise CommercialFinancials::InvalidTerms, 'A proposta precisa estar aceita' unless @proposal.accepted?
        raise CommercialFinancials::InvalidTerms, 'A proposta precisa ter um cliente vinculado' unless @proposal.customer_contact
        existing = @proposal.sales_orders.where.not(status: 'canceled').order(:id).first
        next existing if existing

        terms = @proposal.financial_summary
        snapshot = JrcCrm::ProposalSerializer.new(@proposal).as_json.merge(
          'company_name' => business_unit&.name.presence || 'JRC Conversas',
          'document_brand' => 'JRC Conversas', 'origin' => 'proposal',
          'proposal_number' => @proposal.proposal_number,
          'proposal_version' => @proposal.version_number,
          'accepted_at' => @proposal.accepted_at,
          'first_due_date' => terms[:first_due_date]
        )
        order = JrcCrm::SalesOrder.create!(
          OrderFinancials.attributes_for(terms).merge(
            account: @proposal.account, deal: @proposal.deal, proposal: @proposal,
            contact: @proposal.customer_contact, owner: @proposal.owner || @actor, created_by: @actor,
            business_unit: business_unit, source_type: 'proposal', order_origin: 'proposal_deal',
            proposal_version: @proposal.version_number, sold_at: Time.current,
            snapshot: OrderFinancials.snapshot_for(terms, snapshot)
          )
        )
        terms[:items].each { |item| order.order_items.create!(item) }
        audit_created!(order)
        @created = true
        order
      end
    end

    private

    def audit_created!(order)
      JrcCrm::AuditEvent.create!(
        account_id: order.account_id, actor_type: 'User', actor_id: @actor&.id,
        event_type: 'order_created', resource_type: 'JrcCrm::SalesOrder', resource_id: order.id,
        from_value: {}, to_value: {}, metadata: {
          source: 'accepted_proposal', order_origin: order.order_origin, contact_id: order.contact_id,
          deal_id: order.deal_id, proposal_id: order.proposal_id, proposal_version: order.proposal_version,
          created_at: order.created_at&.iso8601
        }
      )
    rescue StandardError => e
      Rails.logger.warn("JRC CRM proposal-to-order audit failed: #{e.message}")
    end

    def business_unit
      @business_unit ||= JrcCrm::BusinessUnit.find_by(id: @proposal.business_unit_id, account_id: @proposal.account_id)
    end
  end
end
