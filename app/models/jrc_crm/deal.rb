# == Schema Information
#
# Table name: jrc_crm_deals
#
#  id                          :bigint           not null, primary key
#  conversion_key              :string
#  currency                    :string           default("BRL"), not null
#  custom_attributes           :jsonb
#  description                 :text
#  expected_close_at           :datetime
#  lock_version                :integer          default(0), not null
#  lost_at                     :datetime
#  lost_reason_note            :text
#  metadata                    :jsonb
#  probability                 :decimal(5, 2)
#  product_name                :string
#  source                      :string
#  status                      :string           default("open"), not null
#  temperature                 :string           default("warm"), not null
#  title                       :string           not null
#  value_cents                 :bigint           default(0), not null
#  won_at                      :datetime
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :integer          not null
#  company_id                  :bigint
#  contact_id                  :integer
#  lead_id                     :bigint
#  legacy_sales_opportunity_id :bigint
#  lost_reason_id              :bigint
#  organization_id             :bigint
#  owner_id                    :integer          not null
#  pipeline_id                 :bigint           not null
#  stage_id                    :bigint           not null
#  team_id                     :bigint
#
# Indexes
#
#  idx_jrc_crm_deals_account_conversion      (account_id,conversion_key) UNIQUE WHERE (conversion_key IS NOT NULL)
#  idx_jrc_crm_deals_legacy_sales            (account_id,legacy_sales_opportunity_id) UNIQUE WHERE (legacy_sales_opportunity_id IS NOT NULL)
#  index_jrc_crm_deals_on_account_id         (account_id)
#  index_jrc_crm_deals_on_company_id         (company_id)
#  index_jrc_crm_deals_on_expected_close_at  (expected_close_at)
#  index_jrc_crm_deals_on_lead_id            (lead_id)
#  index_jrc_crm_deals_on_organization_id    (organization_id)
#  index_jrc_crm_deals_on_owner_id           (owner_id)
#  index_jrc_crm_deals_on_pipeline_id        (pipeline_id)
#  index_jrc_crm_deals_on_stage_id           (stage_id)
#  index_jrc_crm_deals_on_status             (status)
#  index_jrc_crm_deals_on_team_id            (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (lead_id => jrc_crm_leads.id)
#  fk_rails_...  (lost_reason_id => jrc_crm_lost_reasons.id)
#  fk_rails_...  (organization_id => jrc_crm_organizations.id)
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (pipeline_id => jrc_crm_pipelines.id)
#  fk_rails_...  (stage_id => jrc_crm_stages.id)
#  fk_rails_...  (team_id => teams.id)
#
module JrcCrm
  class Deal < ApplicationRecord
    self.table_name = 'jrc_crm_deals'
    belongs_to :account
    belongs_to :pipeline, class_name: 'JrcCrm::Pipeline'
    belongs_to :stage, class_name: 'JrcCrm::Stage'
    belongs_to :owner, class_name: 'User'
    belongs_to :team, optional: true # Reuses Chatwoot Team
    belongs_to :lost_reason, class_name: 'JrcCrm::LostReason', optional: true
    belongs_to :lead, class_name: 'JrcCrm::Lead', optional: true
    belongs_to :contact, class_name: 'Contact', optional: true
    belongs_to :organization, class_name: 'JrcCrm::Organization', optional: true
    belongs_to :company, optional: true # Enterprise fallback via CompanyAdapter

    has_many :deal_contacts, class_name: 'JrcCrm::DealContact', dependent: :destroy
    has_many :contacts, through: :deal_contacts
    has_many :deal_products, class_name: 'JrcCrm::DealProduct', dependent: :destroy
    has_many :products, through: :deal_products
    has_many :proposals, class_name: 'JrcCrm::Proposal', dependent: :destroy
    has_many :activities, class_name: 'JrcCrm::Activity', foreign_key: :deal_id, dependent: :destroy
    has_many :follow_ups, class_name: 'JrcCrm::FollowUp', foreign_key: :deal_id, dependent: :destroy
    has_many :deal_conversations, class_name: 'JrcCrm::DealConversation', foreign_key: :deal_id, dependent: :destroy
    has_many :conversations, through: :deal_conversations
    has_many :audit_events, -> { where(resource_type: 'JrcCrm::Deal') }, class_name: 'JrcCrm::AuditEvent', foreign_key: :resource_id

    has_many :sales_orders, class_name: 'JrcCrm::SalesOrder', dependent: :restrict_with_error
    has_many :contracts, class_name: 'JrcCrm::Contract', dependent: :restrict_with_error
    validates :title, :pipeline, :stage, :owner, presence: true
    validates :value_cents, numericality: { greater_than_or_equal_to: 0 }
    validates :conversion_key, uniqueness: { scope: :account_id }, allow_nil: true

    enum status: { open: 'open', won: 'won', lost: 'lost', archived: 'archived' }

    validate :lost_reason_required_when_lost
    validate :associations_belong_to_account
    after_save :ensure_primary_contact_link, if: :saved_change_to_contact_id?
    after_update_commit :dispatch_flow_stage_change, if: :saved_change_to_stage_id?

    scope :open_deals, -> { where(status: 'open') }
    scope :won_deals, -> { where(status: 'won') }
    scope :lost_deals, -> { where(status: 'lost') }
    scope :overdue, -> { where('expected_close_at < ? AND status = ?', Time.current, 'open') }
    scope :for_owner, ->(user_id) { where(owner_id: user_id) }
    scope :for_team, ->(team_id) { where(team_id: team_id) if team_id.present? }

    def value
      value_cents / 100.0
    end

    def weighted_value_cents
      (value_cents * probability / 100).to_i if probability
    end

    def last_activity_at
      activities.maximum(:created_at)
    end

    def next_activity
      if activities.loaded?
        activities.select do |activity|
          activity.completed_at.blank? && !activity.status.in?(%w[completed cancelled]) &&
            activity.due_at.present? && activity.due_at >= Time.current
        end.min_by(&:due_at)
      else
        activities.pending.where('due_at >= ?', Time.current).order(:due_at).first
      end
    end

    def overdue?
      status == 'open' && expected_close_at.present? && expected_close_at < Time.current
    end

    def link_conversation!(conversation, actor = nil)
      raise ActiveRecord::RecordNotFound, 'Conversa não pertence à conta do negócio' if conversation.account_id != account_id

      deal_conversations.find_or_create_by!(
        account_id: account_id,
        conversation_id: conversation.id,
        created_by_id: actor&.id
      )
    end

    validate :preserve_project_contact, if: :will_save_change_to_contact_id?

    private

    def preserve_project_contact
      return unless persisted? && JrcOperations::Link.table_exists?
      return unless JrcOperations::Link.where(account_id: account_id, crm_deal_id: id).where.not(project_id: nil).exists?

      errors.add(:contact, 'remova os vinculos com projetos antes de trocar o cliente')
    end

    def dispatch_flow_stage_change
      return if Current.executed_by.is_a?(JrcFlowRun)

      conversations.find_each do |conversation|
        JrcFlows::DispatchJob.perform_later(account_id, conversation.id, 'stage_changed',
          "deal:#{id}:#{stage_id}:#{updated_at.to_f}:#{conversation.id}", nil, stage_id.to_s)
      end
    end

    def lost_reason_required_when_lost
      if status == 'lost' && lost_reason_id.blank? && lost_reason_note.blank?
        errors.add(:base, 'Lost reason is required when deal is lost')
      end
    end


    def associations_belong_to_account
      errors.add(:pipeline, 'must belong to account') if pipeline && pipeline.account_id != account_id
      errors.add(:stage, 'must belong to account') if stage && (stage.account_id != account_id || stage.pipeline_id != pipeline_id)
      errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
      errors.add(:team, 'must belong to account') if team && team.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:lost_reason, 'must belong to account') if lost_reason && lost_reason.account_id != account_id
    end

    def ensure_primary_contact_link
      return if contact_id.blank?

      deal_contacts.find_or_create_by!(contact_id: contact_id)
    end
  end
end
