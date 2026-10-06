# == Schema Information
#
# Table name: jrc_crm_products
#
#  id                           :bigint           not null, primary key
#  activation_days              :integer          default(0), not null
#  active                       :boolean          default(TRUE), not null
#  adjustment_index             :string           default("IPCA"), not null
#  adjustment_period_months     :integer          default(12), not null
#  allow_standalone_sale        :boolean          default(TRUE), not null
#  allow_variable_quantity      :boolean          default(TRUE), not null
#  available_for                :jsonb            not null
#  billing_model                :string           default("one_time"), not null
#  cancellation_penalty_percent :decimal(6, 2)    default(0.0), not null
#  category                     :string
#  commission_rate              :decimal(6, 2)    default(0.0), not null
#  contract_template_name       :string
#  contract_term_months         :integer          default(12), not null
#  cost_cents                   :bigint           default(0), not null
#  currency                     :string           default("BRL")
#  custom_attributes            :jsonb            not null
#  description                  :text
#  discount_approval_percent    :decimal(6, 2)    default(10.0), not null
#  fiscal_service_code          :string
#  included_quantity            :decimal(14, 2)   default(0.0), not null
#  included_unit                :string
#  integrations                 :jsonb            not null
#  maximum_discount_percent     :decimal(6, 2)    default(20.0), not null
#  metadata                     :jsonb            not null
#  minimum_price_cents          :bigint           default(0), not null
#  minimum_quantity             :integer          default(1), not null
#  name                         :string           not null
#  overage_unit_price_cents     :bigint           default(0), not null
#  product_type                 :string           default("service"), not null
#  proposal_template_name       :string
#  renewal_type                 :string           default("automatic"), not null
#  requires_contract            :boolean          default(FALSE), not null
#  rollover_allowance           :boolean          default(FALSE), not null
#  sales_notes                  :text
#  sales_unit                   :string           default("unidade"), not null
#  scope_excluded               :text
#  scope_included               :text
#  setup_fee_cents              :bigint           default(0), not null
#  sku                          :string
#  subcategory                  :string
#  tags                         :jsonb            not null
#  tax_rate                     :decimal(6, 2)    default(0.0), not null
#  technical_requirements       :text
#  unit_price_cents             :bigint           default(0)
#  validation_period_days       :integer          default(0), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :integer          not null
#
# Indexes
#
#  idx_jrc_crm_products_account_billing  (account_id,billing_model)
#  idx_jrc_crm_products_account_sku      (account_id,sku)
#  idx_jrc_crm_products_account_type     (account_id,product_type)
#  index_jrc_crm_products_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
module JrcCrm
  class Product < ApplicationRecord
    self.table_name = 'jrc_crm_products'

    PRODUCT_TYPES = {
      product: 'product',
      service: 'service',
      license: 'license',
      project: 'project'
    }.freeze
    BILLING_MODELS = {
      one_time: 'one_time',
      monthly: 'monthly',
      annual: 'annual',
      usage: 'usage'
    }.freeze
    RENEWAL_TYPES = {
      automatic: 'automatic',
      manual: 'manual',
      none: 'none'
    }.freeze
    ALLOWED_INTEGRATIONS = %w[financial contracts implementation].freeze

    belongs_to :account
    has_many :deal_products, class_name: 'JrcCrm::DealProduct', dependent: :nullify
    has_many :proposal_items, class_name: 'JrcCrm::ProposalItem', dependent: :nullify

    enum product_type: PRODUCT_TYPES, _prefix: :kind
    enum billing_model: BILLING_MODELS, _prefix: :billing
    enum renewal_type: RENEWAL_TYPES, _prefix: :renewal

    validates :name, presence: true
    validates :sku, uniqueness: { scope: :account_id }, allow_blank: true
    validates :unit_price_cents, :cost_cents, :setup_fee_cents, :minimum_price_cents,
              :overage_unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :minimum_quantity, :contract_term_months, :adjustment_period_months,
              numericality: { greater_than: 0 }
    validates :activation_days, :validation_period_days,
              numericality: { greater_than_or_equal_to: 0 }
    validates :included_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :tax_rate, :commission_rate, :maximum_discount_percent,
              :discount_approval_percent, :cancellation_penalty_percent,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :product_type, inclusion: { in: PRODUCT_TYPES.values }
    validates :billing_model, inclusion: { in: BILLING_MODELS.values }
    validates :renewal_type, inclusion: { in: RENEWAL_TYPES.values }
    validate :discount_threshold_is_consistent
    validate :valid_document_rules

    before_validation :normalize_commercial_fields
    validate :price_respects_minimum

    scope :active, -> { where(active: true) }
    scope :recurring, -> { where(billing_model: %w[monthly annual usage]) }

    def unit_price
      unit_price_cents.to_i / 100.0
    end

    def recurring?
      %w[monthly annual usage].include?(billing_model)
    end

    def estimated_margin_cents
      unit_price_cents.to_i - cost_cents.to_i
    end

    def estimated_margin_percent
      return 0.0 unless unit_price_cents.to_i.positive?

      ((estimated_margin_cents.to_f / unit_price_cents.to_i) * 100).round(2)
    end

    def monthly_equivalent_cents
      case billing_model
      when 'monthly', 'usage'
        unit_price_cents.to_i
      when 'annual'
        (unit_price_cents.to_i / 12.0).round
      else
        0
      end
    end

    private

    def valid_document_rules
      valid = document_rules.is_a?(Array) && document_rules.length <= 30 && document_rules.all? do |row|
        row.is_a?(Hash) && row['key'].to_s.match?(/\A[a-z0-9_\-]{1,80}\z/) && row['label'].present? &&
          JrcCrm::BackofficeDocumentChecklist::SOURCES.include?(row['source']) &&
          [true, false].include?(row['required']) && [true, false].include?(row['blocking'])
      end
      errors.add(:document_rules, 'regras documentais inválidas') unless valid
    end

    def discount_threshold_is_consistent
      return if discount_approval_percent.to_f <= maximum_discount_percent.to_f

      errors.add(:discount_approval_percent, 'não pode ser maior que o desconto máximo permitido')
    end

    def normalize_commercial_fields
      self.sku = sku.to_s.strip.presence
      self.sales_unit = sales_unit.to_s.strip.presence || 'unidade'
      self.adjustment_index = adjustment_index.to_s.strip.presence || 'IPCA'
      self.tags = normalize_array(tags)
      self.available_for = normalize_array(available_for)
      self.integrations = normalize_array(integrations) & ALLOWED_INTEGRATIONS
    end

    def price_respects_minimum
      return unless minimum_price_cents.to_i.positive?
      return if unit_price_cents.to_i >= minimum_price_cents.to_i

      errors.add(:unit_price_cents, 'não pode ser menor que o preço mínimo')
    end

    def normalize_array(values)
      Array(values).filter_map { |value| value.to_s.strip.presence }.uniq
    end
  end
end
