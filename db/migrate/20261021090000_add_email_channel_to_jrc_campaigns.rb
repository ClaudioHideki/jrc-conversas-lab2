class AddEmailChannelToJrcCampaigns < ActiveRecord::Migration[7.1]
  def up
    # This migration was moved from 20260904150000 without changing its DDL.
    # Upgraded installations may already contain that exact schema and data.
    if select_value("SELECT version FROM schema_migrations WHERE version = '20260904150000' LIMIT 1")
      verify_legacy_email_schema!
      say 'Verified legacy campaign email migration 20260904150000; existing rows preserved'
      return
    end

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

  private

  def verify_legacy_email_schema!
    tables = %w[jrc_campaigns jrc_campaign_recipients jrc_campaign_sanitized_entries jrc_campaign_steps jrc_campaign_media_assets]
    missing_tables = tables.reject { |table| connection.table_exists?(table) }
    legacy_schema_mismatch!(missing_tables) if missing_tables.any?

    columns = [
      ['jrc_campaigns', 'delivery_channel', :string, false, 'whatsapp', nil],
      ['jrc_campaign_recipients', 'email', :string, true, nil, nil],
      ['jrc_campaign_recipients', 'destination', :string, false, nil, nil],
      ['jrc_campaign_sanitized_entries', 'email', :string, true, nil, nil],
      ['jrc_campaign_sanitized_entries', 'normalized_email', :string, true, nil, nil],
      ['jrc_campaign_steps', 'subject', :string, true, nil, nil],
      ['jrc_campaign_steps', 'media_asset_id', :integer, true, nil, 8]
    ]
    errors = columns.filter_map do |table, name, type, nullable, default, limit|
      column = connection.columns(table).find { |candidate| candidate.name == name }
      compatible = column && column.default_function.nil? &&
                   [column.type, column.null, column.default, column.limit] == [type, nullable, default, limit]
      "#{table}.#{name}" unless compatible
    end
    phone = connection.columns(:jrc_campaign_recipients).find { |column| column.name == 'phone_number' }
    errors << 'jrc_campaign_recipients.phone_number nullability' unless phone&.null

    indexes = [
      ['jrc_campaigns', %w[account_id delivery_channel], false, nil],
      ['jrc_campaign_recipients', %w[execution_id phone_number], true, 'phone_number IS NOT NULL'],
      ['jrc_campaign_recipients', %w[execution_id email], true, 'email IS NOT NULL'],
      ['jrc_campaign_recipients', %w[campaign_id email], false, nil],
      ['jrc_campaign_sanitized_entries', %w[sanitized_list_id normalized_email], false, nil],
      ['jrc_campaign_steps', %w[media_asset_id], false, nil]
    ]
    indexes.each do |table, names, unique, predicate|
      errors << "#{table} index #{names.join('/')}" unless legacy_index_ready?(table, names, unique, predicate)
    end
    errors << 'jrc_campaign_steps.media_asset_id foreign key' unless legacy_media_foreign_key_valid?
    legacy_schema_mismatch!(errors) if errors.any?
  end

  def legacy_index_ready?(table, columns, unique, predicate)
    connection.indexes(table).any? do |index|
      next false unless index.columns == columns && index.unique == unique && normalize_predicate(index.where) == normalize_predicate(predicate)

      connection.select_value(<<~SQL.squish) == true
        SELECT i.indisvalid AND i.indisready
        FROM pg_index i JOIN pg_class idx ON idx.oid = i.indexrelid
        WHERE i.indrelid = #{connection.quote(table)}::regclass AND idx.relname = #{connection.quote(index.name)}
      SQL
    end
  end

  def legacy_media_foreign_key_valid?
    connection.foreign_keys(:jrc_campaign_steps).any? do |key|
      next false unless key.to_table == 'jrc_campaign_media_assets' && Array(key.column) == ['media_asset_id'] &&
                        Array(key.primary_key) == ['id'] && key.options[:on_delete] == :nullify

      connection.select_value(<<~SQL.squish) == true
        SELECT convalidated FROM pg_constraint
        WHERE conrelid = 'jrc_campaign_steps'::regclass AND conname = #{connection.quote(key.name)} AND contype = 'f'
      SQL
    end
  end

  def normalize_predicate(value)
    value.to_s.delete('()"').gsub(/\s+/, ' ').strip.upcase
  end

  def legacy_schema_mismatch!(details)
    raise ActiveRecord::MigrationError,
          "JRC_CAMPAIGNS_LEGACY_SCHEMA_MISMATCH: #{details.join(', ')}. Legacy version is recorded but schema is incompatible; no data changed."
  end
end
