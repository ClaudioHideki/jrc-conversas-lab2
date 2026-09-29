require 'bigdecimal'

module JrcCrm
  module CommissionProtection
    FINAL_STATUSES = %w[paid reversed].freeze
    FINANCIAL_FIELDS = %w[base_cents rate_percent commission_cents share_percent calculation
                          commission_program_id business_unit_id sales_order_id user_id account_id
                          goal_attainment_percent event_key accrued_at released_at paid_at].freeze

    def self.final?(status)
      FINAL_STATUSES.include?(status.to_s)
    end

    def self.changed_fields(changes)
      changes.keys.map(&:to_s) & FINANCIAL_FIELDS
    end

    def self.margin(snapshot)
      values = snapshot.to_h
      value = values.key?('margin_cents') ? values['margin_cents'] : values[:margin_cents]
      return nil if value.nil? || value.to_s.strip.empty?
      amount = BigDecimal(value.to_s)
      amount.finite? ? amount.round(0, BigDecimal::ROUND_HALF_UP).to_i : nil
    rescue ArgumentError
      nil
    end
  end
end
