# == Schema Information
#
# Table name: jrc_crm_activities
#
#  id                       :bigint           not null, primary key
#  activity_type            :string
#  completed_at             :datetime
#  description              :text
#  due_at                   :datetime
#  metadata                 :jsonb
#  status                   :string           default("scheduled"), not null
#  title                    :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :integer          not null
#  company_id               :bigint
#  contact_id               :integer
#  conversation_id          :integer
#  deal_id                  :bigint
#  lead_id                  :bigint
#  legacy_sales_activity_id :bigint
#  organization_id          :bigint
#  user_id                  :integer
#
# Indexes
#
#  idx_jrc_crm_activities_legacy_sales          (account_id,legacy_sales_activity_id) UNIQUE WHERE (legacy_sales_activity_id IS NOT NULL)
#  index_jrc_crm_activities_on_account_id       (account_id)
#  index_jrc_crm_activities_on_activity_type    (activity_type)
#  index_jrc_crm_activities_on_deal_id          (deal_id)
#  index_jrc_crm_activities_on_due_at           (due_at)
#  index_jrc_crm_activities_on_organization_id  (organization_id)
#  index_jrc_crm_activities_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (deal_id => jrc_crm_deals.id)
#  fk_rails_...  (lead_id => jrc_crm_leads.id)
#  fk_rails_...  (organization_id => jrc_crm_organizations.id)
#  fk_rails_...  (user_id => users.id)
#
module JrcCrm
  class Activity < ApplicationRecord
    include JrcCustomers::CrmMasterLink
    self.table_name = 'jrc_crm_activities'
    
    belongs_to :account
    belongs_to :user
    belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
    belongs_to :lead, class_name: 'JrcCrm::Lead', optional: true
    belongs_to :contact, optional: true
    belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
    belongs_to :conversation, optional: true
    
    validates :title, :activity_type, :user, presence: true
    validate :must_have_resource
    validate :associations_belong_to_account
    
    ACTIVITY_TYPES = %w[call whatsapp email meeting task follow_up demonstration visit proposal note system]
    validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
    enum status: { scheduled: 'scheduled', completed: 'completed', cancelled: 'cancelled' }
    
    scope :pending, -> { where(completed_at: nil).where.not(status: %w[completed cancelled]) }
    scope :completed, -> { where.not(completed_at: nil) }
    scope :overdue, -> { pending.where('due_at < ?', Time.current) }
    scope :today, -> { pending.where(due_at: Time.current.all_day) }
    scope :for_owner, ->(user_id) { where(user_id: user_id) }

    def overdue?
      completed_at.blank? && !status.in?(%w[completed cancelled]) && due_at.present? && due_at < Time.current
    end

    def related_record
      deal || lead
    end
    
    private
    
    def must_have_resource
      if deal_id.blank? && lead_id.blank?
        errors.add(:base, 'Activity must belong to a deal or a lead')
      end
    end

    def associations_belong_to_account
      errors.add(:user, 'must belong to account') if user && !account.users.exists?(user.id)
      errors.add(:deal, 'must belong to account') if deal && deal.account_id != account_id
      errors.add(:lead, 'must belong to account') if lead && lead.account_id != account_id
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:conversation, 'must belong to account') if conversation && conversation.account_id != account_id
    end
  end
end
