# == Schema Information
#
# Table name: jrc_crm_invoices
#
#  id               :bigint           not null, primary key
#  balance_cents    :bigint           default(0), not null
#  competence_on    :date
#  discount_cents   :bigint           default(0), not null
#  due_on           :date             not null
#  invoice_number   :string           not null
#  issued_on        :date
#  payment_method   :string
#  snapshot         :jsonb            not null
#  status           :string           default("draft"), not null
#  subtotal_cents   :bigint           default(0), not null
#  tax_cents        :bigint           default(0), not null
#  total_cents      :bigint           default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  business_unit_id :bigint
#  contact_id       :bigint
#  contract_id      :bigint
#  sales_order_id   :bigint
#
# Indexes
#
#  idx_jrc_crm_invoice_number                  (account_id,invoice_number) UNIQUE
#  index_jrc_crm_invoices_on_account_id        (account_id)
#  index_jrc_crm_invoices_on_business_unit_id  (business_unit_id)
#  index_jrc_crm_invoices_on_contact_id        (contact_id)
#  index_jrc_crm_invoices_on_contract_id       (contract_id)
#  index_jrc_crm_invoices_on_sales_order_id    (sales_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (contract_id => jrc_crm_contracts.id)
#  fk_rails_...  (sales_order_id => jrc_crm_sales_orders.id)
#
module JrcCrm
  class Invoice < ApplicationRecord
    self.table_name = 'jrc_crm_invoices'
    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :contact, optional: true
    belongs_to :sales_order, class_name: 'JrcCrm::SalesOrder', optional: true
    belongs_to :contract, class_name: 'JrcCrm::Contract', optional: true
    has_many :payments, class_name: 'JrcCrm::Payment', dependent: :restrict_with_error
    enum status: { draft: 'draft', issued: 'issued', sent: 'sent', paid: 'paid', overdue: 'overdue', canceled: 'canceled' }
    validates :invoice_number, :due_on, presence: true
    validates :invoice_number, uniqueness: { scope: :account_id }
    validate :associations_belong_to_account
    before_validation :assign_number, on: :create

    def recalculate_balance!
      paid_cents = payments.sum(:amount_cents)
      new_balance = [total_cents.to_i - paid_cents, 0].max
      attributes = { balance_cents: new_balance, updated_at: Time.current }
      attributes[:status] = 'paid' if new_balance.zero? && total_cents.to_i.positive?
      update_columns(attributes)
    end

    private

    def associations_belong_to_account
      errors.add(:sales_order, 'must belong to account') if sales_order && sales_order.account_id != account_id
      errors.add(:contract, 'must belong to account') if contract && contract.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
    end

    def assign_number
      self.invoice_number ||= "FAT-#{Time.zone.today.year}-#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
    end
  end
end
