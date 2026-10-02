# == Schema Information
#
# Table name: jrc_crm_leads
#
#  id                :bigint           not null, primary key
#  classified_at     :datetime
#  company_name      :string
#  converted_at      :datetime
#  custom_attributes :jsonb
#  email             :string
#  idempotency_key   :string
#  name              :string           not null
#  notes             :text
#  phone             :string
#  score             :integer          default(0)
#  source            :string
#  status            :string           default("new")
#  temperature       :string           default("warm"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  contact_id        :integer
#  conversation_id   :integer
#  owner_id          :integer          not null
#  team_id           :bigint
#
# Indexes
#
#  idx_jrc_crm_leads_account_idempotency   (account_id,idempotency_key) UNIQUE WHERE (idempotency_key IS NOT NULL)
#  index_jrc_crm_leads_on_account_id       (account_id)
#  index_jrc_crm_leads_on_contact_id       (contact_id)
#  index_jrc_crm_leads_on_conversation_id  (conversation_id)
#  index_jrc_crm_leads_on_email            (email)
#  index_jrc_crm_leads_on_owner_id         (owner_id)
#  index_jrc_crm_leads_on_phone            (phone)
#  index_jrc_crm_leads_on_status           (status)
#  index_jrc_crm_leads_on_team_id          (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (team_id => teams.id)
#
module JrcCrm
  class Lead < ApplicationRecord
    belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
    include JrcCustomers::CrmMasterLink
    self.table_name = 'jrc_crm_leads'
    
    belongs_to :account
    belongs_to :owner, class_name: 'User'
    belongs_to :contact, optional: true
    belongs_to :conversation, optional: true
    belongs_to :team, optional: true
    has_one :deal, class_name: 'JrcCrm::Deal', foreign_key: :lead_id
    has_many :activities, class_name: 'JrcCrm::Activity', foreign_key: :lead_id
    has_many :follow_ups, class_name: 'JrcCrm::FollowUp', foreign_key: :lead_id
    
    validates :name, presence: true
    validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
    validate :associations_belong_to_account
    
    enum status: { new: 'new', in_contact: 'in_contact', qualified: 'qualified', unqualified: 'unqualified', converted: 'converted', lost: 'lost' }, _prefix: true
    
    scope :active, -> { where.not(status: %w[converted unqualified lost]) }
    scope :for_owner, ->(user_id) { where(owner_id: user_id) }

    def public_status
      %w[unqualified lost].include?(status) ? 'discarded' : status
    end
    
    private
    
    def associations_belong_to_account
      errors.add(:owner, 'must belong to account') if owner && !account.users.exists?(owner.id)
      errors.add(:team, 'must belong to account') if team && team.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:conversation, 'must belong to account') if conversation && conversation.account_id != account_id
    end
  end
end
