module JrcCustomers::ContactMaster
  extend ActiveSupport::Concern
  COMPANY_ROLES = %w[decider influencer purchasing finance technical executive requester administrative service_user other].freeze
  COMPANY_CONTEXT_FIELDS = %w[company_id job_title department company_role company_primary company_contact_status].freeze

  included do
    has_many_attached :merged_avatars
    has_one :signing_identity, class_name: 'JrcCustomers::SigningIdentity', dependent: :destroy
    belongs_to :master_company, class_name: 'JrcCustomers::Company', foreign_key: :company_id, optional: true
    has_many :contact_points, class_name: 'JrcCustomers::ContactPoint', dependent: :destroy
    has_many :customer_segment_overrides, class_name: 'JrcCustomers::SegmentOverride', dependent: :destroy
    validate :master_company_belongs_to_account, if: -> { account&.feature_enabled?('jrc_customer_master') && (new_record? || will_save_change_to_company_id?) }
    validates :registration_status, inclusion: { in: %w[provisional registered] }, if: -> { has_attribute?(:registration_status) }
    before_save :sync_master_company_name, if: -> { will_save_change_to_company_id? && account.feature_enabled?('jrc_customer_master') }
    before_validation :reset_company_contact_context, if: :changing_existing_company?
    before_validation :normalize_company_role
    validates :company_role, inclusion: { in: COMPANY_ROLES }, allow_nil: true
    validates :company_contact_status, inclusion: { in: %w[active inactive] }
    validate :company_contact_context_is_valid
  end

  private

  def changing_existing_company?
    persisted? && company_id_in_database.present? && will_save_change_to_company_id? && account.feature_enabled?('jrc_customer_master')
  end

  def normalize_company_role
    self.company_role = company_role.to_s.strip.presence
  end

  def reset_company_contact_context
    self.job_title = nil
    self.department = nil
    self.company_role = nil
    self.company_primary = false
    self.company_contact_status = 'active'
  end

  def company_contact_context_is_valid
    errors.add(:company_role, 'requires a company link') if company_id.blank? && company_role.present?
    return unless company_primary? && (company_id.blank? || company_contact_status != 'active')

    errors.add(:company_primary, 'requires an active company link')
  end

  def master_company_belongs_to_account
    return if company_id.blank?
    return if JrcCustomers::Company.where(account_id: account_id, id: company_id).exists?

    errors.add(:company_id, 'must belong to this account')
  end

  def sync_master_company_name
    self.additional_attributes = (additional_attributes || {}).dup
    if company_id.present?
      additional_attributes['company_name'] = JrcCustomers::Company.where(account_id: account_id).find(company_id).name
    else
      additional_attributes.delete('company_name')
    end
  end
end
