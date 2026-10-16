# == Schema Information
#
# Table name: jrc_crm_proposal_items
#
#  id                       :bigint           not null, primary key
#  activation_days          :integer          default(0), not null
#  billing_model            :string           default("one_time"), not null
#  description_snapshot     :text
#  discount_cents           :bigint           default(0), not null
#  included_quantity        :decimal(14, 2)   default(0.0), not null
#  included_unit            :string
#  initial_total_cents      :bigint           default(0), not null
#  name_snapshot            :string           not null
#  notes                    :text
#  overage_unit_price_cents :bigint           default(0), not null
#  quantity                 :integer          default(1), not null
#  recurring_total_cents    :bigint           default(0), not null
#  setup_fee_cents          :bigint           default(0), not null
#  total_cents              :bigint           default(0), not null
#  unit_name                :string           default("unidade"), not null
#  unit_price_cents         :bigint           default(0), not null
#  validation_period_days   :integer          default(0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  product_id               :bigint
#  proposal_id              :bigint           not null
#
# Indexes
#
#  index_jrc_crm_proposal_items_on_product_id   (product_id)
#  index_jrc_crm_proposal_items_on_proposal_id  (proposal_id)
#
# Foreign Keys
#
#  fk_rails_...  (product_id => jrc_crm_products.id)
#  fk_rails_...  (proposal_id => jrc_crm_proposals.id)
#
module JrcCrm
  class ProposalItem < ApplicationRecord
    self.table_name = 'jrc_crm_proposal_items'
    include JrcCrm::CommercialGratuityIntent

    BILLING_MODELS = %w[one_time monthly annual usage].freeze

    belongs_to :proposal, class_name: 'JrcCrm::Proposal'
    belongs_to :product, class_name: 'JrcCrm::Product', optional: true

    validates :name_snapshot, :quantity, :unit_price_cents, presence: true
    validates :billing_model, inclusion: { in: BILLING_MODELS }
    validates :quantity, numericality: { greater_than: 0 }
    validates :unit_price_cents, :discount_cents, :setup_fee_cents,
              :overage_unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :included_quantity, numericality: { greater_than_or_equal_to: 0 }
    validates :activation_days, :validation_period_days, numericality: { greater_than_or_equal_to: 0 }
    validate :discount_within_product_limit
    validate :price_respects_product_minimum

    before_validation :normalize_fields
    before_validation :calculate_totals
    after_destroy :recalculate_proposal_totals
    after_save :recalculate_proposal_totals

    def recurring?
      %w[monthly annual usage].include?(billing_model)
    end

    def gross_line_total_cents
      unit_price_cents.to_i * quantity.to_i
    end

    def applied_discount_cents
      [discount_cents.to_i, gross_line_total_cents].min
    end

    def gross_initial_total_cents
      setup_fee_cents.to_i + gross_line_total_cents
    end

    private

    def normalize_fields
      self.unit_name = unit_name.to_s.strip.presence || 'unidade'
      self.included_unit = included_unit.to_s.strip.presence
    end

    def calculate_totals
      return unless unit_price_cents && quantity

      net_line_total = gross_line_total_cents - applied_discount_cents
      self.total_cents = net_line_total
      self.recurring_total_cents = recurring_monthly_equivalent(net_line_total)
      self.initial_total_cents = setup_fee_cents.to_i + net_line_total
    end

    def recurring_monthly_equivalent(net_line_total)
      return 0 unless recurring?
      return (net_line_total / 12.0).round if billing_model == 'annual'

      net_line_total
    end

    def discount_within_product_limit
      return unless product
      return if gross_line_total_cents.zero?

      discount_percent = (applied_discount_cents.to_f / gross_line_total_cents) * 100
      return if discount_percent <= product.maximum_discount_percent.to_f

      errors.add(:discount_cents, 'ultrapassa o desconto máximo permitido para este produto')
    end

    def price_respects_product_minimum
      return if declared_free_draft?
      return unless product&.minimum_price_cents.to_i.positive?
      return if unit_price_cents.to_i >= product.minimum_price_cents.to_i

      errors.add(:unit_price_cents, 'não pode ser menor que o preço mínimo do produto')
    end

    def recalculate_proposal_totals
      return if proposal.destroyed? || proposal.marked_for_destruction?

      proposal.recalculate_totals!
    end
  end
end
