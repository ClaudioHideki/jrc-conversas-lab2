require 'bigdecimal'
require 'date'

module JrcCrm
  # One source of truth for proposals, orders and the contractual snapshot.
  # Money is integer cents. Recurring items include their FIRST billing period
  # in the initial price, as in the protected BASE; MRR is reported separately.
  class CommercialFinancials
    VERSION = 2
    class InvalidTerms < ArgumentError; end
    BILLING_MODELS = %w[one_time monthly annual usage].freeze
    PAYMENT_CONDITIONS = %w[cash installments down_payment_installments].freeze
    SHIPPING_MODES = %w[not_applicable included separate].freeze

    def self.symbolize(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), out| out[key.to_sym] = symbolize(item) }
      when Array then value.map { |item| symbolize(item) }
      else value
      end
    end

    def self.stringify(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), out| out[key.to_s] = stringify(item) }
      when Array then value.map { |item| stringify(item) }
      else value
      end
    end

    def self.boolean(value, default: true)
      return default if value.nil?
      ![false, 0, '0', 'false', 'f', 'off', ''].include?(value)
    end

    def self.money(value)
      number = BigDecimal((value.nil? || value == '' ? 0 : value).to_s)
      raise InvalidTerms, 'Valores monetarios devem ser finitos e nao negativos.' unless number.finite? && number >= 0
      number.round(0, BigDecimal::ROUND_HALF_UP).to_i
    rescue ArgumentError => e
      raise e if e.is_a?(InvalidTerms)
      raise InvalidTerms, 'Valor monetario invalido.'
    end

    # Largest-remainder allocation: exact conservation, stable ties, no float drift.
    def self.allocate(total, weights)
      weights = weights.map { |weight| money(weight) }
      return Array.new(weights.length, 0) if weights.sum.zero?
      parts = weights.map { |weight| (money(total) * weight).divmod(weights.sum) }
      remainder = money(total) - parts.sum(&:first)
      parts.each_index.sort_by { |index| [-parts[index][1], index] }.first(remainder).each { |index| parts[index][0] += 1 }
      parts.map(&:first)
    end

    def initialize(attributes:, items:)
      @attributes = self.class.symbolize(attributes.to_h)
      @snapshot = self.class.symbolize((@attributes[:snapshot] || {}).to_h)
      @items = Array(items)
    end

    def normalize_item(raw)
      item = self.class.symbolize(raw.to_h)
      snapshot = self.class.symbolize((item[:snapshot] || {}).to_h)
      quantity = BigDecimal((item[:quantity] || 1).to_s)
      raise InvalidTerms, 'Quantidade deve ser positiva e finita.' unless quantity.finite? && quantity.positive?
      raise InvalidTerms, 'Quantidade aceita no maximo tres casas decimais.' unless quantity == quantity.round(3)
      unit = self.class.money(item.fetch(:unit_cents, item[:unit_price_cents]))
      gross = (quantity * unit).round(0, BigDecimal::ROUND_HALF_UP).to_i
      discount = if item.key?(:discount_percent)
                   percentage(gross, item[:discount_percent])
                 else
                   self.class.money(item[:discount_cents])
                 end
      discount = [discount, gross].min
      net = gross - discount
      billing = item[:billing_model] || snapshot[:billing_model] || 'one_time'
      raise InvalidTerms, 'Modelo de cobranca invalido.' unless BILLING_MODELS.include?(billing)
      setup = self.class.money(item.fetch(:setup_fee_cents, snapshot[:setup_fee_cents]))
      recurring = case billing
                  when 'annual' then (BigDecimal(net.to_s) / 12).round(0, BigDecimal::ROUND_HALF_UP).to_i
                  when 'monthly', 'usage' then net
                  else 0
                  end
      # A manual order can quote an independent future recurring amount while
      # preserving its initial unit price. Persist that explicit term in the
      # item snapshot so reload/recalculation never drops it.
      manual_recurring = snapshot[:manual_recurring_cents]
      manual_recurring = item[:recurring_cents] if manual_recurring.nil? && billing == 'one_time'
      if billing == 'one_time' && !manual_recurring.nil?
        recurring = self.class.money(manual_recurring)
        snapshot = snapshot.merge(manual_recurring_cents: recurring)
      end
      recurring = 0 unless monthly_enabled?
      {
        product_id: (item[:product_id].nil? || item[:product_id].to_s.empty? ? nil : Integer(item[:product_id])), name: item[:name] || item[:name_snapshot], quantity: quantity,
        unit_cents: unit, discount_cents: discount, one_time_cents: setup + net,
        recurring_cents: recurring, snapshot: snapshot.merge(billing_model: billing, setup_fee_cents: setup)
      }
    rescue ArgumentError => e
      raise e if e.is_a?(InvalidTerms)
      raise InvalidTerms, 'Item comercial invalido.'
    end

    def call
      items = @items.map { |item| normalize_item(item) }
      products = items.sum { |item| item[:one_time_cents] }
      products = self.class.money(@attributes[:products_cents]) if items.empty?
      item_discount = items.sum { |item| item[:discount_cents] }
      discount = if @snapshot.key?(:discount_percent) && !@snapshot[:discount_percent].nil?
                   percentage(products, @snapshot[:discount_percent])
                 else
                   self.class.money(@attributes[:discount_cents])
                 end
      discount = [discount, products].min
      shipping_mode = setting(:shipping_mode, self.class.money(@attributes[:shipping_cents]).positive? ? 'separate' : 'not_applicable')
      raise InvalidTerms, 'Modalidade de frete invalida.' unless SHIPPING_MODES.include?(shipping_mode)
      shipping = shipping_mode == 'separate' ? self.class.money(@attributes[:shipping_cents]) : 0
      shipping_in_installments = self.class.boolean(setting(:shipping_in_installments, true))
      taxes = percentage(products - discount + shipping, @snapshot[:taxes_percent] || 0)
      total = products - discount + shipping + taxes
      monthly = monthly_enabled? ? items.sum { |item| item[:recurring_cents] } : 0
      monthly = self.class.money(@attributes[:monthly_cents]) if monthly_enabled? && items.empty?
      condition = setting(:payment_condition, 'cash').to_s
      raise InvalidTerms, 'Condicao de pagamento invalida.' unless PAYMENT_CONDITIONS.include?(condition)
      count = condition == 'cash' ? 1 : integer_count(@attributes[:installments_count] || 1)
      down = condition == 'down_payment_installments' ? self.class.money(@attributes[:down_payment_cents]) : 0
      upfront_shipping = shipping_in_installments ? 0 : shipping
      payable = total - upfront_shipping
      raise InvalidTerms, 'A entrada nao pode exceder o saldo financiavel.' if down > payable
      balance = payable - down
      date_value = [@snapshot[:first_due_date], @attributes[:first_due_date]].find { |date| date && !date.to_s.empty? } || Date.today.iso8601
      first_due = date_value.is_a?(Date) ? date_value : Date.iso8601(date_value.to_s)
      values = condition == 'cash' ? [] : self.class.allocate(balance, Array.new(count, 1))
      installments = values.each_with_index.map do |value, index|
        { number: index + 1, date: (first_due >> index).iso8601, value: value, status: 'Pendente' }
      end
      payments = []
      payments << { kind: 'cash', date: first_due.iso8601, value: balance } if condition == 'cash'
      payments << { kind: 'down_payment', date: first_due.iso8601, value: down } if down.positive?
      payments << { kind: 'shipping', date: first_due.iso8601, value: upfront_shipping } if upfront_shipping.positive?
      payments.concat(installments.map { |row| row.merge(kind: 'installment') })
      raise InvalidTerms, 'Plano financeiro nao conserva o total.' unless payments.sum { |row| row[:value] } == total
      {
        financial_version: VERSION, items: items, subtotal_cents: products + item_discount,
        products_cents: products, item_discount_cents: item_discount, discount_cents: discount,
        total_discount_cents: item_discount + discount, shipping_cents: shipping,
        shipping_mode: shipping_mode, shipping_in_installments: shipping_in_installments,
        taxes_cents: taxes, taxes_percent: BigDecimal((@snapshot[:taxes_percent] || 0).to_s).to_s('F'), total_cents: total, contract_total_cents: total,
        monthly_cents: monthly, has_monthly_fee: monthly_enabled?, payment_condition: condition,
        payment_method: @attributes[:payment_method], down_payment_cents: down,
        payable_base_cents: payable, balance_cents: balance, upfront_shipping_cents: upfront_shipping,
        cash_payment_cents: condition == 'cash' ? balance : 0, installments_count: count,
        installment_plan_cents: values, installments: installments, payments: payments,
        first_due_date: first_due.iso8601
      }
    rescue Date::Error
      raise InvalidTerms, 'Data do primeiro vencimento invalida.'
    end

    private

    def monthly_enabled?
      self.class.boolean(setting(:has_monthly_fee, true))
    end

    def setting(key, fallback)
      value = @attributes.key?(key) ? @attributes[key] : @snapshot.fetch(key, fallback)
      value.nil? ? fallback : value
    end

    def integer_count(value)
      numeric = BigDecimal(value.to_s)
      raise InvalidTerms, 'Quantidade de parcelas deve ser inteira.' unless numeric.finite? && numeric == numeric.round(0)
      count = numeric.to_i
      raise InvalidTerms, 'Quantidade de parcelas deve estar entre 1 e 120.' unless (1..120).cover?(count)
      count
    rescue ArgumentError, TypeError
      raise InvalidTerms, 'Quantidade de parcelas deve estar entre 1 e 120.'
    end

    def percentage(cents, value)
      rate = BigDecimal((value.nil? || value == '' ? 0 : value).to_s)
      raise InvalidTerms, 'Percentual deve estar entre 0 e 100.' unless rate.finite? && rate >= 0 && rate <= 100
      (BigDecimal(cents.to_s) * rate / 100).round(0, BigDecimal::ROUND_HALF_UP).to_i
    rescue ArgumentError => e
      raise e if e.is_a?(InvalidTerms)
      raise InvalidTerms, 'Percentual invalido.'
    end
  end
end
