class JrcCampaigns::TestDelivery < ApplicationRecord
  self.table_name = 'jrc_campaign_test_deliveries'

  belongs_to :account
  belongs_to :inbox
  belongs_to :requested_by, class_name: 'User'

  validates :idempotency_key, :payload_digest, :phone_number, presence: true
  validates :idempotency_key, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: %w[sending sent failed unknown] }
end
