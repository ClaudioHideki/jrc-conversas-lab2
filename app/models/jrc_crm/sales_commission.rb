# == Schema Information
#
# Table name: jrc_crm_sales_commissions
#
#  id                      :bigint           not null, primary key
#  accrued_at              :datetime
#  base_cents              :bigint           default(0), not null
#  calculation             :jsonb            not null
#  commission_cents        :bigint           default(0), not null
#  event_key               :string
#  goal_attainment_percent :decimal(8, 3)
#  notes                   :text
#  paid_at                 :datetime
#  rate_percent            :decimal(7, 3)    default(0.0), not null
#  released_at             :datetime
#  share_percent           :decimal(8, 3)    default(100.0), not null
#  status                  :string           default("forecast"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  business_unit_id        :bigint
#  commission_program_id   :bigint
#  sales_order_id          :bigint           not null
#  user_id                 :bigint           not null
#
# Indexes
#
#  idx_jrc_crm_commission_unique                             (account_id,sales_order_id,user_id) UNIQUE
#  index_jrc_crm_sales_commissions_on_account_id             (account_id)
#  index_jrc_crm_sales_commissions_on_business_unit_id       (business_unit_id)
#  index_jrc_crm_sales_commissions_on_commission_program_id  (commission_program_id)
#  index_jrc_crm_sales_commissions_on_event_key              (event_key)
#  index_jrc_crm_sales_commissions_on_sales_order_id         (sales_order_id)
#  index_jrc_crm_sales_commissions_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (commission_program_id => jrc_crm_commission_programs.id)
#  fk_rails_...  (sales_order_id => jrc_crm_sales_orders.id)
#  fk_rails_...  (user_id => users.id)
#
module JrcCrm
  class SalesCommission < ApplicationRecord
    self.table_name = 'jrc_crm_sales_commissions'
    belongs_to :account
    belongs_to :sales_order, class_name: 'JrcCrm::SalesOrder'
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :commission_program, class_name: 'JrcCrm::CommissionProgram', optional: true
    belongs_to :user

    enum status: { forecast: 'forecast', pending_approval: 'pending_approval', released: 'released', paid: 'paid', reversed: 'reversed' }
    before_validation :calculate_amount, unless: :skip_amount_calculation?
    validate :preserve_final_commission

    validates :rate_percent, numericality: { greater_than_or_equal_to: 0 }
    validates :share_percent, numericality: { greater_than: 0, less_than_or_equal_to: 100 }, allow_nil: true
    validate :associations_belong_to_account

    def calculate_amount
      self.commission_cents = (base_cents.to_i * rate_percent.to_d / 100 * share_percent.to_d / 100).round
    end

    private

    def skip_amount_calculation?
      (persisted? && CommissionProtection.final?(attribute_in_database('status'))) || calculation_supplied?
    end

    def preserve_final_commission
      return unless persisted? && CommissionProtection.final?(attribute_in_database('status'))
      changed = CommissionProtection.changed_fields(changes_to_save)
      errors.add(:base, "Comissao finalizada: campos financeiros imutaveis (#{changed.join(', ')}). Estorne explicitamente para registrar um ajuste separado.") if changed.any?
      if attribute_in_database('status') == 'paid' && !%w[paid reversed].include?(status)
        errors.add(:status, 'comissao paga somente permite estorno explicito')
      end
      if attribute_in_database('status') == 'reversed' && will_save_change_to_status?
        errors.add(:status, 'uma comissao estornada nao pode ser reaberta')
      end
    end

    def calculation_supplied?
      calculation.is_a?(Hash) && (calculation['commission_cents'].present? || calculation[:commission_cents].present?)
    end

    def associations_belong_to_account
      errors.add(:sales_order, 'must belong to account') if sales_order && sales_order.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:commission_program, 'must belong to account') if commission_program && commission_program.account_id != account_id
      errors.add(:user, 'must belong to account') if user && !account.users.exists?(user.id)
    end
  end
end
