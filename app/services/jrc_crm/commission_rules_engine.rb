require 'bigdecimal'

module JrcCrm
  # Pure calculation, shared by simulation and persisted commission synchronization.
  # No Rails dependency is required to test the monetary decisions.
  class CommissionRulesEngine
    def initialize(rules:, sale:, attainment_percent: nil, share_percent: 100)
      @rules = CommercialFinancials.symbolize(rules || {})
      @sale = CommercialFinancials.symbolize(sale || {})
      @attainment_percent = decimal(attainment_percent) unless blank?(attainment_percent)
      @share_percent = decimal(share_percent)
      raise ArgumentError, 'Participacao deve estar entre 0 e 100.' unless @share_percent.between?(0, 100)
    end

    def call
      base = commission_base
      rate, tier = selected_rate(base)
      gross = (base * rate / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
      shared = (gross * @share_percent / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
      bonus = bonus_cents(shared)
      total = shared + bonus
      memory = { base_kind: base_kind, base_cents: base, tier_basis: tier_basis,
                 selected_tier: tier, rate_percent: rate.to_f, share_percent: @share_percent.to_f,
                 attainment_percent: @attainment_percent&.to_f, bonus_cents: bonus, commission_cents: total }
      memory.merge(gross_commission_cents: gross, calculation: memory.dup)
    end

    private

    def blank?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
    end

    def decimal(value)
      result = BigDecimal(blank?(value) ? '0' : value.to_s)
      raise ArgumentError, 'Valor de comissao invalido.' unless result.finite? && result >= 0
      result
    end

    def base_kind
      blank?(@rules[:base]) ? 'total_cents' : @rules[:base].to_s
    end

    def commission_base
      if base_kind == 'margin_cents'
        margin = CommissionProtection.margin(@sale)
        raise ArgumentError, 'Margem indisponivel: nao utilizar o total do pedido.' if margin.nil?
        return [margin, 0].max
      end
      key = %w[monthly_cents received_cents].include?(base_kind) ? base_kind.to_sym : :total_cents
      decimal(@sale[key]).round(0, BigDecimal::ROUND_HALF_UP).to_i
    end

    def tier_basis
      blank?(@rules[:tier_basis]) ? 'sales_value' : @rules[:tier_basis].to_s
    end

    def selected_rate(base)
      value = tier_basis == 'goal_attainment' ? (@attainment_percent || BigDecimal('0')) : base
      tier = Array(@rules[:tiers]).sort_by { |row| minimum_for(row) }.reverse.find do |row|
        maximum = maximum_for(row)
        value >= minimum_for(row) && (maximum.nil? || value <= maximum)
      end
      [decimal(tier&.dig(:rate_percent) || @rules[:rate_percent] || 0), tier]
    end

    def minimum_for(row)
      decimal(row[tier_basis == 'goal_attainment' ? :min_percent : :min_cents])
    end

    def maximum_for(row)
      value = row[tier_basis == 'goal_attainment' ? :max_percent : :max_cents]
      blank?(value) ? nil : decimal(value)
    end

    def bonus_cents(shared)
      Array(@rules[:bonuses]).sum do |bonus|
        next 0 unless @attainment_percent && @attainment_percent >= decimal(bonus[:attainment_percent])
        if blank?(bonus[:amount_cents])
          (shared * decimal(bonus[:percent]) / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
        else
          decimal(bonus[:amount_cents]).round(0, BigDecimal::ROUND_HALF_UP).to_i
        end
      end
    end
  end
end
