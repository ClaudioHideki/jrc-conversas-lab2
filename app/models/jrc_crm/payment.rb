# == Schema Information
#
# Table name: jrc_crm_payments
#
#  id                    :bigint           not null, primary key
#  amount_cents          :bigint           not null
#  discount_cents        :bigint           default(0), not null
#  interest_cents        :bigint           default(0), not null
#  metadata              :jsonb            not null
#  method                :string
#  paid_at               :datetime         not null
#  penalty_cents         :bigint           default(0), not null
#  reconciliation_status :string           default("pending"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  business_unit_id      :bigint
#  external_id           :string
#  invoice_id            :bigint           not null
#
# Indexes
#
#  idx_jrc_crm_payment_external                (account_id,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#  index_jrc_crm_payments_on_account_id        (account_id)
#  index_jrc_crm_payments_on_business_unit_id  (business_unit_id)
#  index_jrc_crm_payments_on_invoice_id        (invoice_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (invoice_id => jrc_crm_invoices.id)
#
module JrcCrm
  class Payment < ApplicationRecord
    self.table_name = 'jrc_crm_payments'
    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :invoice, class_name: 'JrcCrm::Invoice'
    validates :amount_cents, numericality: { greater_than: 0 }
    validates :paid_at, presence: true
    validate :associations_belong_to_account

    private

    def associations_belong_to_account
      errors.add(:invoice, 'must belong to account') if invoice && invoice.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
    end
  end
end
