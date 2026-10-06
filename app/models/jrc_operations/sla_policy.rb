module JrcOperations
  class SlaPolicy < ApplicationRecord
    self.table_name = 'jrc_operations_sla_policies'

    SCOPES = %w[backoffice service_desk crm implementation relationship].freeze

    belongs_to :account
    belongs_to :operations_queue, class_name: 'JrcOperations::Queue', optional: true, inverse_of: :sla_policies

    validates :name, :scope_kind, presence: true
    validates :scope_kind, inclusion: { in: SCOPES }
    validates :first_action_minutes, :stage_minutes, :total_minutes,
              numericality: { only_integer: true, greater_than: 0, allow_nil: true }
    validate :same_account
    validate :valid_calendar

    scope :active, -> { where(active: true) }

    def matches?(order:, request_kind:, priority:, queue:)
      return false if operations_queue_id.present? && operations_queue_id != queue.id
      return false if self.request_kind.present? && self.request_kind != request_kind.to_s
      return false if self.priority.present? && self.priority != priority.to_s

      config = (conditions || {}).with_indifferent_access
      return false unless matches_list?(config[:order_origins], order.order_origin)
      return false unless matches_list?(config[:business_unit_ids], order.business_unit_id)
      return false unless matches_list?(config[:company_ids], order.contact&.company_id)

      product_ids = order.order_items.map(&:product_id).compact.map(&:to_i)
      configured_products = Array(config[:product_ids]).map(&:to_i).reject(&:zero?)
      return false if configured_products.any? && (configured_products & product_ids).empty?

      true
    end

    def effective_pause_statuses
      statuses = Array(pause_statuses).map(&:to_s)
      # Legacy system-generated CS policies only knew waiting_customer. Extend
      # their default without changing explicit policies or any stored setting.
      if scope_kind == 'relationship' && conditions['system_default'] == true && statuses == ['waiting_customer']
        statuses | ['waiting_finance']
      else
        statuses
      end
    end

    def pause_status?(status)
      effective_pause_statuses.include?(status.to_s)
    end

    private

    def valid_calendar
      JrcOperations::BusinessTime.new(business_hours)
    rescue ArgumentError
      errors.add(:business_hours, 'must have valid weekdays and an end after the start')
    end

    def matches_list?(configured, value)
      values = Array(configured).map(&:to_s).reject(&:blank?)
      values.empty? || values.include?(value.to_s)
    end

    def same_account
      errors.add(:operations_queue, 'must belong to account') if operations_queue && operations_queue.account_id != account_id
    end
  end
end
