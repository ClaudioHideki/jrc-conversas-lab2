class AddCampaignConsentSupersession < ActiveRecord::Migration[7.1]
  def change
    add_reference :jrc_campaign_consents, :supersedes, index: { unique: true }, foreign_key: { to_table: :jrc_campaign_consents }
  end
end
