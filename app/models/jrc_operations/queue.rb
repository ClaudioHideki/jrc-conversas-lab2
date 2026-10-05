module JrcOperations
  class Queue < ApplicationRecord
    self.table_name = 'jrc_operations_queues'

    ASSIGNMENT_STRATEGIES = %w[manual round_robin least_load specialty].freeze

    belongs_to :account
    belongs_to :operating_company, class_name: 'JrcCustomers::Company', optional: true
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :team, optional: true
    has_many :sla_policies, class_name: 'JrcOperations::SlaPolicy', foreign_key: :operations_queue_id,
                            dependent: :restrict_with_error, inverse_of: :operations_queue

    validates :name, :code, presence: true
    validates :code, uniqueness: { scope: :account_id }
    validates :assignment_strategy, inclusion: { in: ASSIGNMENT_STRATEGIES }
    validate :same_account

    scope :active, -> { where(active: true) }

    def matches?(order:, request_kind:, priority:)
      return false if operating_company_id.present? && order.business_unit&.company_id != operating_company_id
      return false if business_unit_id.present? && order.business_unit_id != business_unit_id

      config = (settings || {}).with_indifferent_access
      return false unless matches_list?(config[:request_kinds], request_kind)
      return false unless matches_list?(config[:priorities], priority)
      return false unless matches_list?(config[:order_origins], order.order_origin)
      return false unless matches_list?(config[:company_ids], order.contact&.company_id)

      product_ids = order.order_items.map(&:product_id).compact.map(&:to_i)
      configured_products = Array(config[:product_ids]).map(&:to_i).reject(&:zero?)
      return false if configured_products.any? && (configured_products & product_ids).empty?

      true
    end

    def candidate_users
      users = team&.members || account.users
      users = users.where(id: Array((settings || {})['user_ids']).map(&:to_i)) if Array((settings || {})['user_ids']).any?
      users
    end

    private

    def matches_list?(configured, value)
      values = Array(configured).map(&:to_s).reject(&:blank?)
      values.empty? || values.include?(value.to_s)
    end

    def same_account
      errors.add(:operating_company, 'must belong to account') if operating_company && operating_company.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:team, 'must belong to account') if team && team.account_id != account_id
    end
  end
end
