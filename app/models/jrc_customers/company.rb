# Access to the EXISTING companies table, including installations without the
# Enterprise Ruby overlay. Company (EE) and this adapter share the SAME IDs/rows.
class JrcCustomers::Company < ApplicationRecord
  self.table_name = 'companies'
  include JrcCustomers::CompanyRules

  belongs_to :account
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :parent_company, class_name: 'JrcCustomers::Company', optional: true
  has_many :branches, class_name: 'JrcCustomers::Company', foreign_key: :parent_company_id, dependent: :restrict_with_error
  has_many :addresses, class_name: 'JrcCustomers::Address', foreign_key: :company_id, dependent: :restrict_with_error
  has_many :contacts, ->(company) { where(account_id: company.account_id) }, foreign_key: :company_id, dependent: :restrict_with_error
  has_many :legacy_organizations, class_name: 'JrcCrm::Organization', foreign_key: :company_id, dependent: :restrict_with_error

  validates :account_id, :name, presence: true
  validates :name, length: { maximum: 255 }
  validates :domain, uniqueness: { scope: :account_id }, allow_blank: true
  validates :domain, format: { with: /\A[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+\z/ }, allow_blank: true
  validates :custom_attributes, jsonb_attributes_length: true

  scope :ordered, -> { order(:name, :id) }
end
