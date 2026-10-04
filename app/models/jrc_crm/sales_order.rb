# == Schema Information
#
# Table name: jrc_crm_sales_orders
#
#  id                 :bigint           not null, primary key
#  closed_at          :datetime
#  discount_cents     :bigint           default(0), not null
#  down_payment_cents :bigint           default(0), not null
#  installments_count :integer          default(1), not null
#  monthly_cents      :bigint           default(0), not null
#  notes              :text
#  order_number       :string           not null
#  payment_condition  :string
#  payment_method     :string
#  products_cents     :bigint           default(0), not null
#  shipping_cents     :bigint           default(0), not null
#  snapshot           :jsonb            not null
#  sold_at            :datetime
#  source_type        :string           default("proposal"), not null
#  status             :string           default("pending"), not null
#  total_cents        :bigint           default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  business_unit_id   :bigint
#  contact_id         :bigint
#  deal_id            :bigint
#  owner_id           :bigint           not null
#  proposal_id        :bigint
#
# Indexes
#
#  idx_jrc_crm_orders_account_number               (account_id,order_number) UNIQUE
#  index_jrc_crm_sales_orders_on_account_id        (account_id)
#  index_jrc_crm_sales_orders_on_business_unit_id  (business_unit_id)
#  index_jrc_crm_sales_orders_on_contact_id        (contact_id)
#  index_jrc_crm_sales_orders_on_deal_id           (deal_id)
#  index_jrc_crm_sales_orders_on_owner_id          (owner_id)
#  index_jrc_crm_sales_orders_on_proposal_id       (proposal_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (deal_id => jrc_crm_deals.id)
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (proposal_id => jrc_crm_proposals.id)
#
module JrcCrm
  class SalesOrder < ApplicationRecord
    self.table_name = 'jrc_crm_sales_orders'
    belongs_to :account
    belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :proposal, class_name: 'JrcCrm::Proposal', optional: true
    belongs_to :contact, optional: true
    belongs_to :owner, class_name: 'User'
    belongs_to :created_by, class_name: 'User', optional: true
    has_many :order_items, class_name: 'JrcCrm::OrderItem', dependent: :destroy
    has_many_attached :attachments
    has_many :contracts, class_name: 'JrcCrm::Contract', dependent: :restrict_with_error
    has_many :commissions, class_name: 'JrcCrm::SalesCommission', dependent: :destroy
    has_many :backoffice_requests, class_name: 'JrcCrm::BackofficeRequest', dependent: :destroy
    has_many :invoices, class_name: 'JrcCrm::Invoice', dependent: :restrict_with_error
    ORIGINS = %w[proposal_deal direct_sale renewal expansion].freeze
    CONTRACT_ELIGIBLE_STATUSES = %w[approved separating invoiced shipped completed].freeze

    validates :source_type, inclusion: { in: %w[proposal deal manual] }
    validates :order_origin, inclusion: { in: ORIGINS }
    enum status: { draft: 'draft', pending: 'pending', approved: 'approved', separating: 'separating', invoiced: 'invoiced', shipped: 'shipped', completed: 'completed', canceled: 'canceled' }
    validates :order_number, presence: true, uniqueness: { scope: :account_id }
    validate :same_account
    validate :commercial_link_integrity
    validate :order_origin_requires_links
    before_validation :assign_number, on: :create
    def same_account
      errors.add(:deal, 'must belong to account') if deal && deal.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:proposal, 'must belong to account') if proposal && proposal.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
      errors.add(:created_by, 'must belong to account') if created_by && !account.users.exists?(created_by.id)
    end
    def financial_summary
      OrderFinancials.new(attributes: attributes, items: order_items.order(:id).map(&:attributes)).call
    end

    def commercial_link_integrity
      if proposal
        errors.add(:proposal, 'precisa estar aceita para gerar pedido') unless proposal.accepted?
        errors.add(:proposal, 'nao pertence ao negocio selecionado') if deal_id.blank? || proposal.deal_id != deal_id
      end

      return unless deal && contact
      return if contact_matches_deal?

      errors.add(:deal, 'nao pertence ao mesmo cliente do pedido')
    end

    def contact_matches_deal?
      return true if deal.contact_id == contact_id
      return true if deal.deal_contacts.where(contact_id: contact_id).exists?

      contact_company_id = contact.respond_to?(:company_id) ? contact.company_id : nil
      contact_company_id.present? && deal.respond_to?(:company_id) && deal.company_id == contact_company_id
    end

    def order_origin_requires_links
      return unless order_origin == 'proposal_deal'
      return if deal_id.present? || proposal_id.present?

      errors.add(:order_origin, 'Proposta/Negocio exige um negocio ou proposta vinculado')
    end

    def commercial_terms_locked?
      proposal&.accepted? || contracts.exists?
    end

    def assign_number
      return if order_number.present?
      self.order_number = "PED-#{Time.zone.today.year}-#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
    end
  end
end
