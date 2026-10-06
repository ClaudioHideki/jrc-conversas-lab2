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
    include JrcRelationship::SignalDispatch
    include JrcCustomers::CrmMasterLink
    self.table_name = 'jrc_crm_activities'
    
    belongs_to :account
    belongs_to :user
    belongs_to :deal, class_name: 'JrcCrm::Deal', optional: true
    belongs_to :lead, class_name: 'JrcCrm::Lead', optional: true
    belongs_to :contact, optional: true
    belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :conversation, optional: true
    
    validates :title, :activity_type, :user, presence: true
    validate :must_have_resource
    validate :associations_belong_to_account
    after_update :sync_relationship_completion, if: :saved_change_to_status?
    
    ACTIVITY_TYPES = %w[call whatsapp email meeting task follow_up demonstration visit proposal note system]
    validates :activity_type, inclusion: { in: ACTIVITY_TYPES }
    enum status: { scheduled: 'scheduled', completed: 'completed', cancelled: 'cancelled' }
    
    scope :pending, -> { where(completed_at: nil).where.not(status: %w[completed cancelled]) }
    scope :completed, -> { where.not(completed_at: nil) }
    scope :overdue, -> { pending.where("metadata ->> 'relationship_sla_paused_at' IS NULL").where('due_at < ?', Time.current) }
    scope :today, -> { pending.where(due_at: Time.current.all_day) }
    scope :for_owner, ->(user_id) { where(user_id: user_id) }

    def overdue?
      completed_at.blank? && !status.in?(%w[completed cancelled]) && metadata&.dig('relationship_sla_paused_at').blank? && due_at.present? && due_at < Time.current
    end

    def related_record
      deal || lead || contact || company
    end
    
    private

    def sync_relationship_completion
      return unless metadata&.dig('relationship_assignment_id') && account.feature_enabled?('jrc_relationship')

      action = JrcRelationship::Action.where(account_id: account_id, activity_id: id).first
      return unless action

      target = { 'completed' => 'completed', 'cancelled' => 'dismissed', 'scheduled' => 'open' }.fetch(status)
      return if action.status == target || (status == 'scheduled' && JrcRelationship::Action::ACTIVE_STATUSES.include?(action.status))

      actor = Current.user
      actor = user unless actor && account.users.exists?(actor.id)
      action.update!(status: target, result: status == 'completed' ? description.presence || title : action.result,
                     completed_at: status == 'completed' ? completed_at || Time.current : nil,
                     completed_by: status == 'completed' ? actor : nil)
      JrcOperations::SlaClock.new(action).mark_first_action! if status == 'completed'
    end
    
    def must_have_resource
      relationship_origin = metadata&.dig('relationship_assignment_id').present? && (persisted? || account&.feature_enabled?('jrc_relationship'))
      backoffice_origin = metadata&.dig('backoffice_request_id').present? && backoffice_source
      if deal_id.blank? && lead_id.blank? && !((relationship_origin || backoffice_origin) && (contact_id.present? || company_id.present?))
        errors.add(:base, 'Activity must belong to a deal or a lead')
      end
    end

    def backoffice_source
      JrcCrm::BackofficeRequest.where(account_id: account_id).find_by(id: metadata['backoffice_request_id'])
    end

    def associations_belong_to_account
      errors.add(:user, 'must belong to account') if user && !account.users.exists?(user.id)
      errors.add(:deal, 'must belong to account') if deal && deal.account_id != account_id
      errors.add(:lead, 'must belong to account') if lead && lead.account_id != account_id
      errors.add(:company, 'must belong to account') if company && company.account_id != account_id
      if metadata&.dig('relationship_assignment_id').present?
        identity = JrcRelationship::Assignment.where(account_id: account_id).find_by(id: metadata['relationship_assignment_id'])
        errors.add(:base, 'Relationship identity mismatch') unless identity && identity.company_id == company_id && identity.contact_id == contact_id
      end
      if metadata&.dig('backoffice_request_id').present?
        order = backoffice_source&.sales_order
        valid_origin = order && order.contact_id == contact_id && order.contact&.company_id == company_id &&
          (metadata['sales_order_id'].blank? || metadata['sales_order_id'].to_i == order.id)
        errors.add(:base, 'Backoffice identity mismatch') unless valid_origin
      end
      errors.add(:contact, 'must belong to account') if contact && contact.account_id != account_id
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:conversation, 'must belong to account') if conversation && conversation.account_id != account_id
    end
  end
end
