# Membership deliberately keeps the existing companies.economic_group value.
# Imports, saved criteria and old clients retain their exact names and IDs.
class JrcCustomers::EconomicGroup < ApplicationRecord
  self.table_name = 'jrc_customer_economic_groups'

  belongs_to :account
  belongs_to :principal_company, class_name: 'JrcCustomers::Company', optional: true
  has_many :companies, ->(group) { where(account_id: group.account_id) },
           class_name: 'JrcCustomers::Company', foreign_key: :economic_group, primary_key: :name,
           dependent: :restrict_with_error, inverse_of: false

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :name, length: { maximum: 65_536 }, if: :will_save_change_to_name?
  validates :description, length: { maximum: 5000 }, allow_nil: true
  validate :principal_is_member
  validate :preserve_used_name

  scope :ordered, -> { order(:name, :id) }

  def criteria_dependents?
    criteria = { rules: [{ field: 'economic_group', value: name_in_database || name }] }
    JrcCustomers::Taxonomy.where(account_id: account_id).exists?(['criteria @> ?::jsonb', criteria.to_json])
  end

  private

  def principal_is_member
    return if principal_company_id.blank?
    return if JrcCustomers::Company.where(account_id: account_id, economic_group: name).exists?(id: principal_company_id)

    errors.add(:principal_company_id, 'must be a member company in this account')
  end

  def preserve_used_name
    return unless persisted? && will_save_change_to_name?
    return unless JrcCustomers::Company.exists?(account_id: account_id, economic_group: name_in_database) || criteria_dependents?

    errors.add(:name, 'cannot rename a group used by companies or saved segment criteria')
  end
end
