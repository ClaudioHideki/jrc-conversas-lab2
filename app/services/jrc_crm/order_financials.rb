module JrcCrm
  # Public adapter retained for existing controllers and the UI preview endpoint.
  class OrderFinancials
    STORED_FIELDS = %i[products_cents shipping_cents discount_cents total_cents monthly_cents
                       payment_condition payment_method down_payment_cents installments_count].freeze
    TERM_FIELDS = %i[products_cents shipping_cents shipping_mode shipping_in_installments discount_cents
                     taxes_cents total_cents monthly_cents has_monthly_fee payment_condition payment_method
                     down_payment_cents installments_count first_due_date installment_plan_cents].freeze

    def self.attributes_for(result)
      result.select { |key, _| STORED_FIELDS.include?(key) }
    end

    def self.snapshot_for(result, original = {})
      snapshot = CommercialFinancials.stringify(original.to_h)
      CommercialFinancials.stringify(snapshot.merge(
        'financial_version' => CommercialFinancials::VERSION,
        'document_brand' => 'JRC Conversas',
        'shipping_mode' => result[:shipping_mode],
        'shipping_in_installments' => result[:shipping_in_installments],
        'has_monthly_fee' => result[:has_monthly_fee],
        'first_due_date' => result[:first_due_date],
        'taxes_cents' => result[:taxes_cents],
        'taxes_percent' => result[:taxes_percent],
        'discount_percent' => nil,
        'installments' => result[:installments],
        'payments' => result[:payments],
        'financials' => result.except(:items)
      ))
    end

    def self.same_terms?(left, right)
      left.slice(*TERM_FIELDS) == right.slice(*TERM_FIELDS) &&
        left[:items].map { |row| row.slice(:product_id, :quantity, :unit_cents, :discount_cents, :one_time_cents, :recurring_cents) } ==
          right[:items].map { |row| row.slice(:product_id, :quantity, :unit_cents, :discount_cents, :one_time_cents, :recurring_cents) }
    end

    def initialize(attributes:, items:)
      @calculator = CommercialFinancials.new(attributes: attributes, items: items)
    end

    def call
      @calculator.call
    end

    def normalize_item(item)
      @calculator.normalize_item(item)
    end
  end
end
