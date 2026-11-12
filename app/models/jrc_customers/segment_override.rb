class JrcCustomers::SegmentOverride < ApplicationRecord
  self.table_name = 'jrc_customer_segment_overrides'

  belongs_to :account
  belongs_to :taxonomy, class_name: 'JrcCustomers::Taxonomy'
  belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
  belongs_to :contact, optional: true

  validates :mode, inclusion: { in: %w[include exclude] }
  validate :same_account_subject

  private

  def same_account_subject
    errors.add(:base, 'Choose exactly one company or contact') if company_id.nil? == contact_id.nil?
    [taxonomy, company, contact].compact.each do |record|
      errors.add(:base, 'Reference must belong to this account') unless record.account_id == account_id
    end
  end
end
