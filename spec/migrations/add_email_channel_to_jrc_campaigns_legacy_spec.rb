require 'rails_helper'
require 'tmpdir'
require 'fileutils'
require Rails.root.join('db/migrate/20261021090000_add_email_channel_to_jrc_campaigns').to_s

RSpec.describe AddEmailChannelToJrcCampaigns, type: :model do
  let(:connection) { ActiveRecord::Base.connection }
  let(:migration) { described_class.new }

  before do
    @previous_search_path = connection.schema_search_path
    @fixture_schema = "ura_campaign_upgrade_#{SecureRandom.hex(6)}"
    connection.create_schema(@fixture_schema)
    connection.schema_search_path = @fixture_schema
    connection.schema_cache.clear!
    connection.create_table(:schema_migrations, id: false) { |t| t.string :version, null: false }
    connection.add_index(:schema_migrations, :version, unique: true)
    connection.create_table(:jrc_campaigns) { |t| t.bigint :account_id }
    connection.create_table(:jrc_campaign_recipients) do |t|
      t.bigint :campaign_id
      t.bigint :execution_id
      t.string :phone_number, null: false
    end
    connection.add_index(:jrc_campaign_recipients, [:execution_id, :phone_number], unique: true,
                         name: 'index_jrc_campaign_recipients_on_execution_id_and_phone_number')
    connection.create_table(:jrc_campaign_sanitized_entries) { |t| t.bigint :sanitized_list_id }
    connection.create_table(:jrc_campaign_steps) { |t| t.bigint :campaign_id }
    connection.create_table(:jrc_campaign_media_assets)
    connection.execute('INSERT INTO jrc_campaigns (account_id) VALUES (1)')
    connection.execute("INSERT INTO jrc_campaign_recipients (campaign_id, execution_id, phone_number) VALUES (1, 1, '+5511000000000')")
  end

  after do
    connection.schema_search_path = @previous_search_path if @previous_search_path
    connection.schema_cache.clear!
    # The schema and its rows are also covered by RSpec's transaction rollback.
  end

  def installed_email_schema!(legacy_version: true)
    migration.up
    connection.execute("UPDATE jrc_campaigns SET delivery_channel = 'email'")
    connection.execute(<<~SQL.squish)
      INSERT INTO jrc_campaign_recipients (campaign_id, execution_id, phone_number, email, destination)
      VALUES (1, 1, NULL, 'preserve@example.test', 'preserve@example.test')
    SQL
    return unless legacy_version

    connection.execute("INSERT INTO schema_migrations (version) VALUES ('20260904150000')")
  end

  def row_snapshot
    %w[jrc_campaigns jrc_campaign_recipients].to_h do |table|
      [table, connection.select_all("SELECT * FROM #{connection.quote_table_name(table)} ORDER BY id").to_a]
    end
  end

  it 'upgrades the original pre-email schema and backfills the existing phone destination' do
    migration.up

    expect(connection.select_value('SELECT destination FROM jrc_campaign_recipients')).to eq('+5511000000000')
    expect(connection.select_value('SELECT delivery_channel FROM jrc_campaigns')).to eq('whatsapp')
    expect(connection.columns(:jrc_campaign_recipients).find { |c| c.name == 'phone_number' }.null).to be(true)
  end

  it 'recognizes the applied legacy timestamp only after verifying the complete schema and preserves email-only data' do
    installed_email_schema!
    before_rows = row_snapshot
    before_indexes = connection.indexes(:jrc_campaign_recipients).map(&:name).sort

    expect { migration.up }.not_to raise_error
    expect(row_snapshot).to eq(before_rows)
    expect(connection.indexes(:jrc_campaign_recipients).map(&:name).sort).to eq(before_indexes)
  end

  it 'does not silently adopt existing columns when the legacy history is absent' do
    installed_email_schema!(legacy_version: false)
    before_rows = row_snapshot

    expect { connection.transaction(requires_new: true) { migration.up } }.to raise_error(ActiveRecord::StatementInvalid)
    expect(row_snapshot).to eq(before_rows)
  end

  it 'rejects a missing unique email index before changing any rows' do
    installed_email_schema!
    connection.remove_index(:jrc_campaign_recipients, name: 'index_jrc_campaign_recipients_on_execution_id_and_email')
    before_rows = row_snapshot

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /LEGACY_SCHEMA_MISMATCH/)
    expect(row_snapshot).to eq(before_rows)
  end

  it 'rejects an incompatible column default before changing any rows' do
    installed_email_schema!
    connection.change_column_default(:jrc_campaigns, :delivery_channel, 'email')
    before_rows = row_snapshot

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /LEGACY_SCHEMA_MISMATCH/)
    expect(row_snapshot).to eq(before_rows)
  end

  it 'rejects a missing media foreign key' do
    installed_email_schema!
    connection.remove_foreign_key(:jrc_campaign_steps, column: :media_asset_id)

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /LEGACY_SCHEMA_MISMATCH/)
  end

  it 'rejects a functional default even when its parsed scalar default is nil' do
    installed_email_schema!
    connection.execute("ALTER TABLE jrc_campaign_steps ALTER COLUMN subject SET DEFAULT current_setting('application_name')")
    subject_column = connection.columns(:jrc_campaign_steps).find { |column| column.name == 'subject' }
    expect(subject_column.default).to be_nil
    expect(subject_column.default_function).to be_present

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /LEGACY_SCHEMA_MISMATCH/)
  end

  it 'rejects an existing but unvalidated media foreign key' do
    installed_email_schema!
    connection.remove_foreign_key(:jrc_campaign_steps, column: :media_asset_id)
    connection.add_foreign_key(:jrc_campaign_steps, :jrc_campaign_media_assets, column: :media_asset_id, on_delete: :nullify, validate: false)

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /LEGACY_SCHEMA_MISMATCH/)
  end

  it 'rejects the wrong predicate on an otherwise matching unique email index' do
    installed_email_schema!
    name = 'index_jrc_campaign_recipients_on_execution_id_and_email'
    connection.remove_index(:jrc_campaign_recipients, name: name)
    connection.add_index(:jrc_campaign_recipients, [:execution_id, :email], name: name, unique: true, where: 'email IS NULL')

    expect { migration.up }.to raise_error(ActiveRecord::MigrationError, /LEGACY_SCHEMA_MISMATCH/)
  end

  it 'lets Rails record the renamed version after the verified no-op without rewriting data' do
    installed_email_schema!
    before_rows = row_snapshot

    Dir.mktmpdir('ura-campaign-migration-') do |directory|
      FileUtils.cp(Rails.root.join('db/migrate/20261021090000_add_email_channel_to_jrc_campaigns.rb'), directory)
      context = ActiveRecord::MigrationContext.new(directory, ActiveRecord::SchemaMigration.new(connection),
                                                 ActiveRecord::InternalMetadata.new(connection))
      context.migrate
      expect(context.get_all_versions).to include(20_260_904_150_000, 20_261_021_090_000)
    end
    expect(row_snapshot).to eq(before_rows)
  end
end
