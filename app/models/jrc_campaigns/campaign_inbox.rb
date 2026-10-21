# == Schema Information
#
# Table name: jrc_campaign_inboxes
#
#  id          :bigint           not null, primary key
#  enabled     :boolean          default(TRUE), not null
#  position    :integer          default(0), not null
#  weight      :integer          default(1), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  campaign_id :bigint           not null
#  inbox_id    :integer          not null
#
# Indexes
#
#  index_jrc_campaign_inboxes_on_campaign_id               (campaign_id)
#  index_jrc_campaign_inboxes_on_campaign_id_and_inbox_id  (campaign_id,inbox_id) UNIQUE
#  index_jrc_campaign_inboxes_on_inbox_id                  (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => jrc_campaigns.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class JrcCampaigns::CampaignInbox < ApplicationRecord
  self.table_name = 'jrc_campaign_inboxes'

  belongs_to :campaign, class_name: 'JrcCampaigns::Campaign'
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :campaign_id }
  validates :weight, numericality: { greater_than: 0 }
  validate :inbox_belongs_to_campaign_account
  validate :channel_matches_campaign

  private

  def inbox_belongs_to_campaign_account
    errors.add(:inbox, 'deve pertencer à mesma conta') if inbox && inbox.account_id != campaign.account_id
  end
  def channel_matches_campaign
    return unless inbox && campaign
    return if campaign.accepts_sending_inbox?(inbox)

    channel_name = campaign.email? ? 'E-mail' : 'WhatsApp'
    errors.add(:inbox, "deve ser uma caixa de #{channel_name}")
  end
end
