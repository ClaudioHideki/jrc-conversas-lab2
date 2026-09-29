# == Schema Information
#
# Table name: jrc_crm_commission_programs
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(TRUE), not null
#  ends_on           :date
#  name              :string           not null
#  release_condition :string           default("order_approved"), not null
#  rules             :jsonb            not null
#  starts_on         :date
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  business_unit_id  :bigint
#
# Indexes
#
#  index_jrc_crm_commission_programs_on_account_id        (account_id)
#  index_jrc_crm_commission_programs_on_business_unit_id  (business_unit_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#
module JrcCrm
  class CommissionProgram < ApplicationRecord
    self.table_name = 'jrc_crm_commission_programs'
    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    has_many :sales_commissions, class_name: 'JrcCrm::SalesCommission', dependent: :restrict_with_error

    validates :name, :release_condition, presence: true
    validates :release_condition, inclusion: { in: %w[order_approved contract_signed payment_received implementation_completed] }
    validate :business_unit_belongs_to_account
    validate :rules_are_coherent

    scope :active, -> { where(active: true) }

    def eligible_for?(order)
      product_ids = ids_rule('product_ids')
      user_ids = ids_rule('user_ids')
      team_ids = ids_rule('team_ids')
      return false if starts_on.present? && order_date(order) < starts_on
      return false if ends_on.present? && order_date(order) > ends_on
      return false if product_ids.any? && !order.order_items.where(product_id: product_ids).exists?
      return false if user_ids.any? && !user_ids.include?(order.owner_id)
      return true if team_ids.empty?

      order.account.teams.joins(:members).where(id: team_ids, users: { id: order.owner_id }).exists?
    end

    def commission_base_cents(order, base_key: nil)
      product_ids = ids_rule('product_ids')
      key = base_key.presence || rule_value('base').presence || 'total_cents'
      if product_ids.empty?
        return order.monthly_cents.to_i if key == 'monthly_cents'
        return order.total_cents.to_i
      end

      values = CommercialItemAllocation.call(items: order.order_items.to_a,
        discount_cents: order.discount_cents, monthly_enabled: order.monthly_cents.to_i.positive?)
      column = key == 'monthly_cents' ? :monthly_cents : :revenue_cents
      values.select { |row| product_ids.include?(row[:product_id].to_i) }.sum { |row| row[column] }
    end

    def product_restriction?
      ids_rule('product_ids').any?
    end

    def rules_hash
      rules.is_a?(Hash) ? rules.with_indifferent_access : {}
    end

    private

    def order_date(order)
      (order.sold_at || order.closed_at || order.created_at).to_date
    end

    def ids_rule(key)
      Array(rule_value(key)).map(&:to_i).reject(&:zero?)
    end

    def business_unit_belongs_to_account
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
    end

    def rules_are_coherent
      data = rules_hash
      tier_basis = data[:tier_basis].presence || 'sales_value'
      unless tier_basis.in?(%w[sales_value goal_attainment])
        errors.add(:rules, 'tier_basis inválido')
      end
      base = data[:base].presence || 'total_cents'
      unless base.in?(%w[total_cents monthly_cents received_cents margin_cents])
        errors.add(:rules, 'base comissionável inválida')
      end
      errors.add(:rules, 'percentual base não pode ser negativo') if data[:rate_percent].to_d.negative?
      share = data[:share_percent].presence || 100
      errors.add(:rules, 'rateio deve estar entre 0 e 100%') unless share.to_d.positive? && share.to_d <= 100
      if tier_basis == 'goal_attainment' && Array(data[:goal_ids]).blank?
        errors.add(:rules, 'faixas por atingimento exigem ao menos uma meta vinculada')
      end
      Array(data[:tiers]).each do |row|
        tier = row.with_indifferent_access
        rate = tier[:rate_percent].to_d
        errors.add(:rules, 'percentual de faixa não pode ser negativo') if rate.negative?
        min = tier_basis == 'goal_attainment' ? tier[:min_percent].to_d : tier[:min_cents].to_d
        max_raw = tier_basis == 'goal_attainment' ? tier[:max_percent] : tier[:max_cents]
        max = max_raw.present? ? max_raw.to_d : nil
        errors.add(:rules, 'limite mínimo de faixa não pode ser negativo') if min.negative?
        errors.add(:rules, 'limite máximo da faixa não pode ser menor que o mínimo') if max && max < min
      end
    end

    def rule_value(key)
      return rules[key] || rules[key.to_sym] if rules.is_a?(Hash)

      Array(rules).find { |rule| rule.is_a?(Hash) && rule['key'] == key }&.dig('value')
    end
  end
end
