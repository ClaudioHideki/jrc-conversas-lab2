class JrcRelationship::Assignment < ApplicationRecord
  self.table_name = 'jrc_relationship_assignments'
  belongs_to :account
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  belongs_to :contact, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :team, optional: true
  belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
  has_many :actions, class_name: 'JrcRelationship::Action', dependent: :restrict_with_error
  validates :status, inclusion: { in: %w[onboarding active at_risk churned inactive] }
  validate :identity_and_tenant

  def customer_context(member)
    JrcCustomers::Customer360.new(account: account, user: member.user, account_user: member, company: company, contact: contact)
  end

  def label
    company&.name || contact&.name
  end

  private

  def identity_and_tenant
    errors.add(:base, 'Choose one existing company or contact') unless [company_id, contact_id].compact.one?
    %i[company contact team business_unit].each do |key|
      value = public_send(key)
      errors.add(key, 'must belong to this account') if value && value.account_id != account_id
    end
    errors.add(:owner, 'must belong to this account') if owner && !account.users.exists?(owner.id)
    # business_unit belongs to the internal operating Company; company is the
    # served master customer. They are intentionally different identities.
    %w[segment_id product_id].each do |key|
      id = settings[key]
      next if id.blank?
      model = key == 'segment_id' ? JrcCustomers::Taxonomy : JrcCrm::Product
      errors.add(:settings, "#{key} must belong to this account") unless model.where(account_id: account_id, id: id).exists?
    end
  end
end
