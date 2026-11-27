class AddCampaignTemplateMediaSource < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_campaign_media_assets, :source_key, :string
    add_index :jrc_campaign_media_assets, [:account_id, :source_key], unique: true,
                                                                      where: 'source_key IS NOT NULL', name: 'idx_campaign_template_media_source'
  end
end
