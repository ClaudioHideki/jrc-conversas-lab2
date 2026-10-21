class AddEmailChannelToJrcCampaigns < ActiveRecord::Migration[7.1]
  def up
    add_column :jrc_campaigns, :delivery_channel, :string, null: false, default: 'whatsapp'
    add_index :jrc_campaigns, [:account_id, :delivery_channel]

    add_column :jrc_campaign_recipients, :email, :string
    add_column :jrc_campaign_recipients, :destination, :string
    change_column_null :jrc_campaign_recipients, :phone_number, true
    execute <<~SQL.squish
      UPDATE jrc_campaign_recipients
      SET destination = phone_number
      WHERE destination IS NULL
    SQL
    change_column_null :jrc_campaign_recipients, :destination, false

    remove_index :jrc_campaign_recipients,
                 name: 'index_jrc_campaign_recipients_on_execution_id_and_phone_number'
    add_index :jrc_campaign_recipients, [:execution_id, :phone_number],
              unique: true,
              where: 'phone_number IS NOT NULL',
              name: 'index_jrc_campaign_recipients_on_execution_id_and_phone_number'
    add_index :jrc_campaign_recipients, [:execution_id, :email],
              unique: true,
              where: 'email IS NOT NULL'
    add_index :jrc_campaign_recipients, [:campaign_id, :email]

    add_column :jrc_campaign_sanitized_entries, :email, :string
    add_column :jrc_campaign_sanitized_entries, :normalized_email, :string
    add_index :jrc_campaign_sanitized_entries, [:sanitized_list_id, :normalized_email],
              name: 'idx_jrc_sanitized_entries_list_email'

    add_column :jrc_campaign_steps, :subject, :string
    add_reference :jrc_campaign_steps,
                  :media_asset,
                  foreign_key: { to_table: :jrc_campaign_media_assets, on_delete: :nullify }
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'Campanhas de e-mail podem possuir destinatários sem telefone; restaure um backup para voltar à V11.'
  end
end
