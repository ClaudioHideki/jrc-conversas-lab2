require 'rails_helper'
require Rails.root.join('db/migrate/20261120090000_create_contact_center_audio_folders')

RSpec.describe CreateContactCenterAudioFolders do
  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Audio folder migration requires an exclusively owned disposable database' unless owned
  end

  def in_owned_preupgrade_schema
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('CREATE SCHEMA cc_audio_folder_upgrade_synthetic')
      %w[accounts jrc_contact_center_units].each do |table|
        connection.execute("CREATE TABLE cc_audio_folder_upgrade_synthetic.#{table} (LIKE public.#{table} INCLUDING ALL)")
      end
      previous = connection.schema_search_path
      begin
        connection.schema_search_path = 'cc_audio_folder_upgrade_synthetic'
        yield connection
      ensure
        connection.schema_search_path = previous
      end
      raise ActiveRecord::Rollback
    end
  end

  it 'adds an empty library organization to populated native units without changing their data' do
    account = create(:account)
    unit = JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC populated', kind: 'sac')
    in_owned_preupgrade_schema do |connection|
      connection.execute("INSERT INTO accounts SELECT * FROM public.accounts WHERE id = #{account.id}")
      connection.execute("INSERT INTO jrc_contact_center_units SELECT * FROM public.jrc_contact_center_units WHERE id = #{unit.id}")
      before = connection.select_one("SELECT * FROM jrc_contact_center_units WHERE id = #{unit.id}")
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_audio_folders').to_i).to eq(0)
      expect(connection.select_one("SELECT * FROM jrc_contact_center_units WHERE id = #{unit.id}")).to eq(before)
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_audio_folders').to_i).to eq(0)
    end
    expect(unit.reload.name).to eq('SYNTHETIC populated')
  end

  it 'verifies both fresh and reloaded real schemas idempotently' do
    count = JrcContactCenter::AudioFolder.count
    described_class.new.up
    described_class.new.up
    expect(JrcContactCenter::AudioFolder.count).to eq(count)
    expect(ActiveRecord::Base.connection.foreign_keys(:jrc_contact_center_audio_folders).length).to eq(3)
  end

  it 'blocks reexecution when the origin foreign key has been removed rather than accepting a divergent table' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      key = connection.foreign_keys(:jrc_contact_center_audio_folders).find { |row| row.to_table == 'jrc_contact_center_units' }
      connection.remove_foreign_key(:jrc_contact_center_audio_folders, name: key.name)
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio folder schema/)
    end
  end

  it 'does not silently delete folder history in migration rollback' do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /separately reviewed rollback/)
  end
end
