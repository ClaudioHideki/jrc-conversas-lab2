class RenameCampaignStatusProviderErrors < ActiveRecord::Migration[7.1]
  def change
    rename_column :jrc_campaign_status_events, :errors, :provider_errors
  end
end
