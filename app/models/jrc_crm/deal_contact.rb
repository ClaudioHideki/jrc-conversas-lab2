# == Schema Information
#
# Table name: jrc_crm_deal_contacts
#
#  id         :bigint           not null, primary key
#  role       :string           default("primary")
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  contact_id :integer          not null
#  deal_id    :bigint           not null
#
# Indexes
#
#  index_jrc_crm_deal_contacts_on_deal_id_and_contact_id  (deal_id,contact_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (deal_id => jrc_crm_deals.id)
#
module JrcCrm
  class DealContact < ApplicationRecord
    self.table_name = 'jrc_crm_deal_contacts'
    
    belongs_to :deal, class_name: 'JrcCrm::Deal'
    belongs_to :contact
    
    validate :same_account

    def same_account
      errors.add(:contact_id, 'must belong to the deal account') unless contact&.account_id == deal&.account_id
    end

    validates :deal_id, :contact_id, presence: true
    validates :contact_id, uniqueness: { scope: :deal_id }
  end
end
