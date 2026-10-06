# == Schema Information
#
# Table name: jrc_crm_proposals
#
#  id                           :bigint           not null, primary key
#  accepted_at                  :datetime
#  accepted_by_document         :string
#  accepted_by_name             :string
#  accepted_from_ip             :string
#  accepted_user_agent          :string
#  annual_adjustment_index      :string           default("IPCA"), not null
#  approval_status              :string           default("not_required"), not null
#  billing_day                  :integer
#  canceled_at                  :datetime
#  cancellation_penalty_percent :decimal(6, 2)    default(0.0), not null
#  commercial_approval_status   :string           default("not_required"), not null
#  commercial_notes             :text
#  customer_notes               :text
#  discount_cents               :bigint           default(0), not null
#  down_payment_cents           :bigint           default(0), not null
#  financial_approval_status    :string           default("not_required"), not null
#  first_billing_days           :integer          default(0), not null
#  follow_up_days               :integer          default(3), not null
#  follow_up_enabled            :boolean          default(TRUE), not null
#  has_monthly_fee              :boolean          default(TRUE), not null
#  implementation_cents         :bigint           default(0), not null
#  installments_count           :integer          default(1), not null
#  issuer_company_name          :string           default("Grupo JRC"), not null
#  issuer_unit                  :string
#  last_sent_channel            :string
#  last_viewed_at               :datetime
#  lock_version                 :integer          default(0), not null
#  locked_at                    :datetime
#  monthly_cents                :bigint           default(0), not null
#  next_steps                   :text
#  notes                        :text
#  payment_condition            :string           default("cash"), not null
#  payment_method               :string
#  proposal_number              :string           not null
#  public_token_digest          :string           not null
#  public_token_expires_at      :datetime
#  public_token_revoked_at      :datetime
#  rejected_at                  :datetime
#  renewal_type                 :string           default("automatic"), not null
#  sent_at                      :datetime
#  shipping_cents               :bigint           default(0), not null
#  shipping_in_installments     :boolean          default(TRUE), not null
#  shipping_mode                :string           default("not_applicable"), not null
#  solution_description         :text
#  status                       :string           default("draft"), not null
#  subtotal_cents               :bigint           default(0), not null
#  taxes_included               :boolean          default(TRUE), not null
#  technical_approval_status    :string           default("not_required"), not null
#  term_months                  :integer          default(12), not null
#  title                        :string           not null
#  total_cents                  :bigint           default(0), not null
#  valid_until                  :date
#  version_number               :integer          default(1), not null
#  viewed_at                    :datetime
#  viewed_count                 :integer          default(0), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :integer          not null
#  business_unit_id             :bigint
#  deal_id                      :bigint           not null
#  issuer_tax_id                :string
#  last_sent_conversation_id    :integer
#  last_sent_message_id         :bigint
#  owner_id                     :integer          not null
#
# Indexes
#
#  idx_jrc_crm_proposals_account_number                  (account_id,proposal_number) UNIQUE
#  index_jrc_crm_proposals_on_account_id                 (account_id)
#  index_jrc_crm_proposals_on_business_unit_id           (business_unit_id)
#  index_jrc_crm_proposals_on_deal_id                    (deal_id)
#  index_jrc_crm_proposals_on_last_sent_conversation_id  (last_sent_conversation_id)
#  index_jrc_crm_proposals_on_last_sent_message_id       (last_sent_message_id)
#  index_jrc_crm_proposals_on_public_token_digest        (public_token_digest) UNIQUE
#  index_jrc_crm_proposals_on_status                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (deal_id => jrc_crm_deals.id)
#  fk_rails_...  (owner_id => users.id)
#
require 'digest'
require 'securerandom'

module JrcCrm
  class Proposal < ApplicationRecord
    self.table_name = 'jrc_crm_proposals'
    attr_accessor :raw_public_token

    STATUS_VALUES = %w[draft pending_approval sent viewed accepted rejected canceled].freeze
    APPROVAL_VALUES = %w[not_required pending approved rejected].freeze

    def relationship_origin
      events.where(event_type: %w[created duplicated]).order(:id).pick(:metadata)&.dig('relationship_origin') || {}
    end

    belongs_to :account
    belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
    belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
    belongs_to :contact, optional: true
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :owner, class_name: 'User'
    has_many :items, class_name: 'JrcCrm::ProposalItem', foreign_key: :proposal_id, dependent: :destroy
    has_many :events, class_name: 'JrcCrm::ProposalEvent', foreign_key: :proposal_id, dependent: :destroy
    has_many :proposal_items, class_name: 'JrcCrm::ProposalItem', foreign_key: :proposal_id, dependent: :destroy
    has_many :sales_orders, class_name: 'JrcCrm::SalesOrder', dependent: :restrict_with_error

    validates :title, presence: true
    validates :proposal_number, presence: true, uniqueness: { scope: :account_id }
    validates :public_token_digest, presence: true, uniqueness: true
    validates :implementation_cents, :monthly_cents, :discount_cents,
              numericality: { greater_than_or_equal_to: 0 }
    validates :term_months, numericality: { greater_than: 0 }
    validates :billing_day, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 31 }, allow_nil: true
    validates :first_billing_days, :follow_up_days, numericality: { greater_than_or_equal_to: 0 }
    validates :cancellation_penalty_percent,
              numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :shipping_mode, inclusion: { in: %w[not_applicable included separate] }
    validates :payment_condition, inclusion: { in: %w[cash down_payment_installments installments] }
    validates :shipping_cents, :down_payment_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :installments_count, numericality: { greater_than: 0, less_than_or_equal_to: 120 }
    validates :approval_status, :commercial_approval_status,
              :financial_approval_status, :technical_approval_status,
              inclusion: { in: APPROVAL_VALUES }

    enum status: STATUS_VALUES.index_with(&:itself)

    validate :owner_belongs_to_account
    validate :customer_identity_is_consistent
    validate :payment_terms_are_consistent
    validate :customer_transition_is_valid

    before_validation :generate_secure_public_token, on: :create
    before_validation :assign_proposal_number, on: :create

    scope :active, -> { where.not(status: ['canceled', 'rejected']) }
    scope :not_expired, -> { where('public_token_expires_at IS NULL OR public_token_expires_at > ?', Time.current) }
    scope :not_revoked, -> { where(public_token_revoked_at: nil) }

    def self.find_by_raw_token(raw_token, allow_unavailable: false)
      return nil if raw_token.blank?

      digest = Digest::SHA256.hexdigest(raw_token.to_s)
      proposal = find_by(public_token_digest: digest)
      return proposal if proposal && (allow_unavailable || proposal.token_valid?)

      payload = token_verifier.verify(raw_token.to_s, purpose: 'jrc-crm-public-proposal')
      return nil unless payload.is_a?(Hash)

      proposal = find_by(id: payload['proposal_id'], account_id: payload['account_id'])
      proposal && (allow_unavailable || proposal.token_valid?) ? proposal : nil
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def self.token_verifier
      @token_verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key('jrc-crm-proposal'),
        digest: 'SHA256',
        serializer: JSON,
        url_safe: true
      )
    end

    def token_valid?
      return false if public_token_revoked_at.present?
      return false if public_token_expires_at.present? && public_token_expires_at < Time.current

      true
    end

    def locked_for_editing?
      locked_at.present? || accepted?
    end

    def customer_response_allowed?
      public_availability[:available] && (sent? || viewed?)
    end

    def public_availability
      JrcCrm::ProposalPublicState.call(self)
    end

    def record_expiration!
      with_lock do
        return unless public_availability[:state] == 'expired'
        return if events.where(event_type: 'expired').exists?

        events.create!(account_id: account_id, event_type: 'expired', description: 'Prazo de validade da proposta expirado',
                       metadata: { origin: 'public_link', channel: 'web', expired_at: public_token_expires_at || valid_until })
      end
    end

    def revoke!(reason = nil)
      update!(public_token_revoked_at: Time.current, status: 'canceled')
      events.create!(
        account_id: account_id,
        event_type: 'revoked',
        description: "Proposta revogada#{": #{reason}" if reason.present?}"
      )
    end

    def public_token
      raw_public_token.presence || self.class.token_verifier.generate(
        { 'proposal_id' => id, 'account_id' => account_id },
        purpose: 'jrc-crm-public-proposal'
      )
    end

    def expires_at
      public_token_expires_at
    end

    def customer_contact
      contact || deal&.contact || deal&.contacts&.first
    end

    def linked_conversation
      deal&.conversations&.order(updated_at: :desc)&.first || customer_contact&.conversations&.order(updated_at: :desc)&.first
    end

    def customer_company
      company || deal&.company || customer_contact&.company
    end

    def item_discount_cents
      proposal_items.to_a.sum(&:applied_discount_cents)
    end

    def effective_general_discount_cents
      available_after_item_discounts = if proposal_items.any?
                                         initial_items_cents
                                       else
                                         implementation_cents.to_i + monthly_cents.to_i
                                       end
      [discount_cents.to_i, available_after_item_discounts].min
    end

    def total_discount_cents
      item_discount_cents + effective_general_discount_cents
    end

    def initial_items_cents
      proposal_items.to_a.sum(&:initial_total_cents)
    end

    # Same engine and initial-period semantics used by SalesOrder.
    def financial_items
      records = proposal_items.to_a
      return records.map do |item|
        { product_id: item.product_id, name: item.name_snapshot, quantity: item.quantity,
          unit_cents: item.unit_price_cents, discount_cents: item.discount_cents,
          snapshot: { description: item.description_snapshot, billing_model: item.billing_model,
                      unit_name: item.unit_name, setup_fee_cents: item.setup_fee_cents,
                      included_quantity: item.included_quantity, included_unit: item.included_unit,
                      overage_unit_price_cents: item.overage_unit_price_cents,
                      activation_days: item.activation_days, validation_period_days: item.validation_period_days } }
      end if records.any?

      rows = [{ name: 'Valor inicial', quantity: 1, unit_cents: implementation_cents.to_i,
                snapshot: { billing_model: 'one_time' } }]
      if has_monthly_fee? && monthly_cents.to_i.positive?
        rows << { name: 'Primeiro periodo de recorrencia', quantity: 1, unit_cents: monthly_cents.to_i,
                  snapshot: { billing_model: 'monthly' } }
      end
      rows
    end

    def financial_summary
      published_anchor = if persisted?
                           events.where(event_type: 'sent').order(:id).pluck(:metadata).filter_map do |metadata|
                             metadata.to_h['financial_anchor_on']
                           end.first
                         end
      anchor = published_anchor.present? ? Date.iso8601(published_anchor) : (sent_at || accepted_at || created_at || Time.current).to_date
      due_date = anchor + first_billing_days.to_i
      CommercialFinancials.new(
        attributes: attributes.merge('first_due_date' => due_date.iso8601),
        items: financial_items
      ).call
    end

    def recalculate_totals!
      proposal_items.reset
      result = financial_summary
      columns = {
        subtotal_cents: result[:subtotal_cents], total_cents: result[:total_cents],
        monthly_cents: result[:monthly_cents], shipping_cents: result[:shipping_cents],
        down_payment_cents: result[:down_payment_cents], installments_count: result[:installments_count],
        updated_at: Time.current
      }
      columns[:implementation_cents] = proposal_items.to_a.sum { |item| item.setup_fee_cents.to_i } if proposal_items.any?
      update_columns(columns)
    end

    def contract_total_cents
      financial_summary[:total_cents]
    end

    def payable_base_cents
      financial_summary[:payable_base_cents]
    end

    def installment_plan_cents
      financial_summary[:installment_plan_cents]
    end

    def reset_approvals!
      update_columns(
        status: 'draft',
        approval_status: 'not_required',
        commercial_approval_status: 'not_required',
        financial_approval_status: 'not_required',
        technical_approval_status: 'not_required',
        updated_at: Time.current
      )
    end

    def record_customer_view!(origin: 'public_link', channel: 'web')
      with_lock do
        return false unless customer_response_allowed?

        now = Time.current
        count = viewed_count.to_i + 1
        update!(viewed_at: viewed_at || now, last_viewed_at: now,
                viewed_count: count, status: sent? ? 'viewed' : status)
        events.create!(account_id: account_id, event_type: 'viewed',
                       description: count == 1 ? 'Proposta visualizada pelo cliente' : 'Proposta visualizada novamente pelo cliente',
                       metadata: { view_number: count, repeated: count > 1, origin: origin, channel: channel })
      end
      true
    end

    def accept_by_customer!(name:, document:, remote_ip:, user_agent:)
      unless customer_response_allowed?
        errors.add(:status, 'não permite aceite antes do envio da proposta')
        raise ActiveRecord::RecordInvalid, self
      end

      update!(
        status: 'accepted',
        accepted_at: Time.current,
        accepted_by_name: name,
        accepted_by_document: document,
        accepted_from_ip: remote_ip,
        accepted_user_agent: user_agent,
        locked_at: Time.current
      )
    end

    private

    def customer_transition_is_valid
      return unless will_save_change_to_status?
      protected_transition = %w[viewed accepted rejected].include?(status)
      valid = JrcCrm::ProposalPublicState.transition_allowed?(from: status_in_database, to: status, sent_at: sent_at)
      return if valid && (!protected_transition || public_availability[:available])

      errors.add(:status, 'exige envio oficial antes de visualização, aceite ou recusa')
    end

    def customer_identity_is_consistent
      errors.add(:base, 'Selecione um negócio ou um cliente do Cadastro Mestre') unless deal || company || contact
      [deal, company, contact, business_unit].compact.each do |record|
        errors.add(:base, 'Referência de outra account não permitida') unless record.account_id == account_id
      end
      errors.add(:contact, 'deve pertencer à empresa selecionada') if company && contact && company_id != contact.company_id
      return unless deal

      errors.add(:company, 'deve corresponder ao negócio') if company_id.present? && deal.company_id != company_id
      if contact_id.present? && deal.contact_id != contact_id && !deal.deal_contacts.exists?(contact_id: contact_id)
        errors.add(:contact, 'deve corresponder ao negócio')
      end
    end

    def owner_belongs_to_account
      errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
    end

    def payment_terms_are_consistent
      financial_summary
    rescue CommercialFinancials::InvalidTerms => e
      errors.add(:base, e.message)
    end

    def assign_proposal_number
      return if proposal_number.present?

      year = Time.current.year
      token = SecureRandom.hex(3).upcase
      self.proposal_number = "PROP-#{year}-#{token}"
    end

    def generate_secure_public_token
      return if public_token_digest.present?

      token = SecureRandom.urlsafe_base64(32)
      self.raw_public_token = token
      self.public_token_digest = Digest::SHA256.hexdigest(token)
      self.public_token_expires_at ||= 30.days.from_now
    end
  end
end
