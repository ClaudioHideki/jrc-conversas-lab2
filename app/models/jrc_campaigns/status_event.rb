class JrcCampaigns::StatusEvent < ApplicationRecord
  self.table_name = 'jrc_campaign_status_events'

  belongs_to :inbox
  validates :external_id, :status, :fingerprint, :occurred_at, presence: true
end
