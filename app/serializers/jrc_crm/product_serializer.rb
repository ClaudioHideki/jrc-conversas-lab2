module JrcCrm
  class ProductSerializer
    def initialize(product, include_commercial_sensitive: true)
      @product = product
      @include_commercial_sensitive = include_commercial_sensitive
    end

    def as_json(options = {})
      data = {
        id: @product.id,
        name: @product.name,
        sku: @product.sku,
        product_type: @product.product_type,
        category: @product.category,
        subcategory: @product.subcategory,
        description: @product.description,
        tags: Array(@product.tags),
        sales_unit: @product.sales_unit,
        billing_model: @product.billing_model,
        recurring: @product.recurring?,
        unit_price_cents: @product.unit_price_cents,
        monthly_equivalent_cents: @product.monthly_equivalent_cents,
        setup_fee_cents: @product.setup_fee_cents,
        minimum_price_cents: @product.minimum_price_cents,
        tax_rate: @product.tax_rate.to_f,
        commission_rate: @product.commission_rate.to_f,
        included_quantity: @product.included_quantity.to_f,
        included_unit: @product.included_unit,
        overage_unit_price_cents: @product.overage_unit_price_cents,
        minimum_quantity: @product.minimum_quantity,
        allow_variable_quantity: @product.allow_variable_quantity,
        activation_days: @product.activation_days,
        validation_period_days: @product.validation_period_days,
        rollover_allowance: @product.rollover_allowance,
        contract_term_months: @product.contract_term_months,
        maximum_discount_percent: @product.maximum_discount_percent.to_f,
        discount_approval_percent: @product.discount_approval_percent.to_f,
        renewal_type: @product.renewal_type,
        adjustment_index: @product.adjustment_index,
        adjustment_period_months: @product.adjustment_period_months,
        cancellation_penalty_percent: @product.cancellation_penalty_percent.to_f,
        allow_standalone_sale: @product.allow_standalone_sale,
        requires_contract: @product.requires_contract,
        fiscal_service_code: @product.fiscal_service_code,
        available_for: Array(@product.available_for),
        integrations: Array(@product.integrations),
        document_rules: @product.document_rules,
        proposal_template_name: @product.proposal_template_name,
        contract_template_name: @product.contract_template_name,
        sales_notes: @product.sales_notes,
        technical_requirements: @product.technical_requirements,
        scope_included: @product.scope_included,
        scope_excluded: @product.scope_excluded,
        currency: @product.currency.presence || 'BRL',
        active: @product.active,
        created_at: @product.created_at,
        updated_at: @product.updated_at
      }

      return data unless @include_commercial_sensitive

      data.merge(
        cost_cents: @product.cost_cents,
        estimated_margin_cents: @product.estimated_margin_cents,
        estimated_margin_percent: @product.estimated_margin_percent
      )
    end
  end
end
