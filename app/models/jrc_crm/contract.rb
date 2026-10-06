# == Schema Information
#
# Table name: jrc_crm_contracts
#
#  id                    :bigint           not null, primary key
#  adjustment_index      :string           default("IPCA")
#  auto_renew            :boolean          default(FALSE), not null
#  content_override      :text
#  contract_number       :string           not null
#  contract_type         :string
#  due_day               :integer
#  ends_on               :date
#  lifecycle_metadata    :jsonb            not null
#  monthly_cents         :bigint           default(0), not null
#  next_adjustment_on    :date
#  notes                 :text
#  one_time_cents        :bigint           default(0), not null
#  payment_condition     :string
#  renewal_notice_days   :integer          default(30), not null
#  renewal_term_months   :integer
#  renewal_type          :string           default("automatic")
#  signature_mode        :string
#  signature_provider    :string
#  signature_status      :string           default("not_started"), not null
#  signed_at             :datetime
#  signed_by_name        :string
#  starts_on             :date
#  status                :string           default("draft"), not null
#  term_months           :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  business_unit_id      :bigint
#  contact_id            :bigint
#  contract_template_id  :bigint
#  deal_id               :bigint
#  owner_id              :bigint           not null
#  sales_order_id        :bigint           not null
#  signature_external_id :string
#  source_contract_id    :bigint
#
# Indexes
#
#  idx_jrc_crm_contracts_account_number             (account_id,contract_number) UNIQUE
#  index_jrc_crm_contracts_on_account_id            (account_id)
#  index_jrc_crm_contracts_on_business_unit_id      (business_unit_id)
#  index_jrc_crm_contracts_on_contact_id            (contact_id)
#  index_jrc_crm_contracts_on_contract_template_id  (contract_template_id)
#  index_jrc_crm_contracts_on_deal_id               (deal_id)
#  index_jrc_crm_contracts_on_owner_id              (owner_id)
#  index_jrc_crm_contracts_on_sales_order_id        (sales_order_id)
#  index_jrc_crm_contracts_on_source_contract_id    (source_contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (contract_template_id => jrc_crm_contract_templates.id)
#  fk_rails_...  (deal_id => jrc_crm_deals.id)
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (sales_order_id => jrc_crm_sales_orders.id)
#  fk_rails_...  (source_contract_id => jrc_crm_contracts.id)
#
module JrcCrm
  class Contract < ApplicationRecord
    include JrcRelationship::SignalDispatch
    self.table_name = 'jrc_crm_contracts'
    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :contract_template, class_name: 'JrcCrm::ContractTemplate', optional: true
    has_many :contract_items, class_name: 'JrcCrm::ContractItem', dependent: :destroy
    has_many_attached :documents
    has_one_attached :signed_document
    belongs_to :source_contract, class_name: 'JrcCrm::Contract', optional: true
    has_many :derived_contracts, class_name: 'JrcCrm::Contract', foreign_key: :source_contract_id, dependent: :nullify
    has_many :invoices, class_name: 'JrcCrm::Invoice', dependent: :restrict_with_error
    belongs_to :sales_order, class_name: 'JrcCrm::SalesOrder'
    belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
    belongs_to :contact, optional: true
    belongs_to :owner, class_name: 'User'
    enum status: { draft: 'draft', awaiting_signature: 'awaiting_signature', active: 'active', expiring: 'expiring', renewed: 'renewed', ended: 'ended' }
    validates :contract_number, presence: true, uniqueness: { scope: :account_id }
    validates :signature_status, inclusion: { in: %w[not_started prepared sent signed canceled failed] }, allow_nil: true
    validates :signature_mode, inclusion: { in: %w[manual provider] }, allow_blank: true
    validate :associations_belong_to_account
    validate :commercial_stage_is_valid
    before_validation :assign_number, on: :create
    before_validation :inherit_order_terms, on: :create
    validate :preserve_financial_snapshot, on: :update

    def financial_summary
      stored = (lifecycle_metadata || {})['financials']
      return stored.with_indifferent_access if stored.present?
      sales_order.financial_summary.except(:items).with_indifferent_access
    end

    def commercial_stage_is_valid
      if persisted? && will_save_change_to_signature_status? && attribute_in_database('signature_status') == 'signed' && signature_status != 'signed'
        errors.add(:signature_status, 'a assinatura registrada deve ser preservada')
      end
      if new_record? && sales_order && !JrcCrm::OrderWorkflowSyncService::QUALIFYING_STATUSES.include?(sales_order.status)
        errors.add(:sales_order, 'precisa estar aprovado antes de gerar contrato')
      end
      if will_save_change_to_status? && %w[active expiring renewed].include?(status) && signature_status != 'signed'
        errors.add(:status, 'exige assinatura registrada')
      end
      if will_save_change_to_signature_status? && signature_status == 'signed' &&
         (signed_at.blank? || signed_by_name.blank? || !signed_document.attached?)
        errors.add(:signature_status, 'exige documento assinado, data e signatário')
      end
    end

    def inherit_order_terms
      return unless sales_order
      terms = source_contract && source_contract.sales_order_id == sales_order_id ? source_contract.financial_summary : sales_order.financial_summary
      self.one_time_cents = terms[:total_cents]
      self.monthly_cents = terms[:monthly_cents]
      self.payment_condition = terms[:payment_condition]
      self.lifecycle_metadata = (lifecycle_metadata || {}).merge(
        'document_brand' => 'JRC Conversas',
        'financials' => terms.except(:items).deep_stringify_keys
      )
    end

    def preserve_financial_snapshot
      if %w[one_time_cents monthly_cents payment_condition sales_order_id].any? { |key| will_save_change_to_attribute?(key) }
        errors.add(:base, 'Valores do pedido/contrato sao preservados. Use um fluxo explicito de nova negociacao ou aditivo.')
      end
      previous = (attribute_in_database('lifecycle_metadata') || {})['financials']
      current = (lifecycle_metadata || {})['financials']
      errors.add(:lifecycle_metadata, 'o snapshot financeiro nao pode ser alterado') if previous.present? && previous != current
    end

    def assign_number
      self.contract_number ||= "CTR-#{Time.zone.today.year}-#{SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')}"
    end

    def associations_belong_to_account
      errors.add(:sales_order, 'must belong to account') if sales_order && sales_order.account_id != account_id
      errors.add(:deal, 'must belong to account') if deal && deal.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:contract_template, 'must belong to account') if contract_template && contract_template.account_id != account_id
      errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
      errors.add(:source_contract, 'must belong to account') if source_contract && source_contract.account_id != account_id
    end
  end
end
