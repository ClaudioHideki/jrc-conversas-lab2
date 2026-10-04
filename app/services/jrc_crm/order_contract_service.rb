module JrcCrm
  # Creates the primary contract for an approved commercial order when the
  # order snapshot or sold products require a contract.
  class OrderContractService
    def initialize(order:, actor: nil)
      @order = order
      @actor = actor || order.owner
    end

    def call
      return unless contract_required?

      existing = primary_contract
      return existing if existing

      @order.with_lock do
        existing = primary_contract
        next existing if existing

        proposal = @order.proposal
        starts_on = parse_date(snapshot[:activation_date]) || Date.current
        term_months = proposal&.term_months.to_i
        term_months = product_term_months if term_months <= 0
        term_months = 12 if term_months <= 0

        contract = @order.account.jrc_crm_contracts.create!(
          sales_order: @order,
          deal: @order.deal,
          contact: @order.contact,
          owner: @order.owner,
          business_unit: @order.business_unit,
          status: 'draft',
          starts_on: starts_on,
          ends_on: starts_on.advance(months: term_months) - 1.day,
          term_months: term_months,
          renewal_type: proposal&.renewal_type.presence || 'automatic',
          adjustment_index: proposal&.annual_adjustment_index.presence || 'IPCA',
          due_day: proposal&.billing_day,
          auto_renew: proposal&.renewal_type.to_s == 'automatic',
          renewal_term_months: term_months,
          notes: "Contrato gerado automaticamente a partir do pedido #{@order.order_number}",
          lifecycle_metadata: { 'source' => 'sales_order_automation' }
        )
        copy_items!(contract)
        audit!(contract)
        contract
      end
    end

    private

    def snapshot
      @snapshot ||= (@order.snapshot || {}).with_indifferent_access
    end

    def contract_required?
      return true if ActiveModel::Type::Boolean.new.cast(snapshot[:generate_contract])
      return true if @order.monthly_cents.to_i.positive?

      @order.order_items.includes(:product).any? do |item|
        product = item.product
        product && (product.requires_contract? || Array(product.integrations).include?('contracts'))
      end
    end

    def primary_contract
      @order.contracts.where(source_contract_id: nil).order(:id).first
    end

    def product_term_months
      @order.order_items.includes(:product).filter_map { |item| item.product&.contract_term_months }.map(&:to_i).max.to_i
    end

    def copy_items!(contract)
      @order.order_items.find_each do |item|
        contract.contract_items.create!(
          product: item.product,
          name: item.name,
          quantity: item.quantity,
          one_time_cents: item.one_time_cents,
          monthly_cents: item.recurring_cents,
          snapshot: item.snapshot.merge('unit_cents' => item.unit_cents, 'discount_cents' => item.discount_cents)
        )
      end
    end

    def audit!(contract)
      JrcCrm::AuditLoggerService.new(
        account: @order.account,
        event_type: 'contract_created',
        actor: @actor,
        resource: contract,
        from_value: '',
        to_value: 'draft',
        metadata: { sales_order_id: @order.id, deal_id: @order.deal_id, source: 'sales_order_automation' }
      ).call
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
