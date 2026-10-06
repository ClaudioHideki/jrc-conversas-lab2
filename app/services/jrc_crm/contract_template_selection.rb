module JrcCrm
  class ContractTemplateSelection
    KEYS = %w[operating_company_id product_ids order_origins payment_conditions term_months customer_kind].freeze

    def self.match?(rules, context)
      return false unless rules.is_a?(Hash) && (rules.keys.map(&:to_s) - KEYS).empty?
      rules.all? do |key, value|
        next true if value.nil? || value == '' || value == []
        actual = context[key.to_s] || context[key.to_sym]
        case key.to_s
        when 'product_ids' then (Array(value).map(&:to_s) & Array(actual).map(&:to_s)).any?
        when 'order_origins', 'payment_conditions' then Array(value).map(&:to_s).include?(actual.to_s)
        else value.to_s == actual.to_s
        end
      end
    end

    def self.select(templates, context)
      templates.select { |row| match?(row.selection_rules || {}, context) }
        .sort_by { |row| [-row.selection_rules.values.count { |value| !value.nil? && value != '' && value != [] }, row.id] }.first
    end

    def self.context(order)
      company = order.contact&.company || order.deal&.company
      tax_id = company&.tax_id.presence || order.contact&.identifier
      { 'operating_company_id' => order.business_unit&.company_id,
        'product_ids' => order.order_items.pluck(:product_id).compact,
        'order_origins' => order.order_origin, 'payment_conditions' => order.payment_condition,
        'term_months' => order.proposal&.term_months.presence || order.order_items.includes(:product).filter_map { |row| row.product&.contract_term_months }.max || 12,
        'customer_kind' => tax_id.to_s.gsub(/\D/, '').length == 14 ? 'pj' : 'pf' }
    end
  end
end
