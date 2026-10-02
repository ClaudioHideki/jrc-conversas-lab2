module JrcCustomers::ContactMaster
  extend ActiveSupport::Concern
  included do
    has_many_attached :merged_avatars
    belongs_to :master_company, class_name: 'JrcCustomers::Company', foreign_key: :company_id, optional: true
    has_many :contact_points, class_name: 'JrcCustomers::ContactPoint', dependent: :destroy
    validate :master_company_belongs_to_account, if: -> { account&.feature_enabled?('jrc_customer_master') && (new_record? || will_save_change_to_company_id?) }
    validates :registration_status, inclusion: { in: %w[provisional registered] }, if: -> { has_attribute?(:registration_status) }
    before_save :sync_master_company_name, if: -> { will_save_change_to_company_id? && account.feature_enabled?('jrc_customer_master') }
  end

  private

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
