require 'rails_helper'
require Rails.root.join('db/migrate/20261120120000_create_contact_center_audio_files')

RSpec.describe CreateContactCenterAudioFiles do
  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' &&
            %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic].include?(config.database)
    raise 'Audio file schema requires an exclusively owned disposable database' unless owned
  end

  # A new transactional schema in this job's synthetic DB; no original tables are changed or removed.
  def in_owned_preupgrade_schema
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('CREATE SCHEMA cc_audio_files_upgrade_synthetic')
      tables = %w[accounts users account_users jrc_contact_center_units jrc_contact_center_audio_folders
                  active_storage_blobs active_storage_attachments]
      tables.each { |table| connection.execute("CREATE TABLE cc_audio_files_upgrade_synthetic.#{table} (LIKE public.#{table} INCLUDING ALL)") }
      previous = connection.schema_search_path
      begin
        connection.schema_search_path = 'cc_audio_files_upgrade_synthetic'
        yield connection
      ensure
        connection.schema_search_path = previous
      end
      raise ActiveRecord::Rollback
    end
  end

  it 'adds an empty private version library to populated native units without rewriting existing unit data' do
    account = create(:account)
    unit = JrcContactCenter::Unit.create!(account: account, code: 'SYNTHETIC', name: 'SYNTHETIC populated audio unit', kind: 'sac')
    folder = JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC existing folder')
    in_owned_preupgrade_schema do |connection|
      %w[accounts jrc_contact_center_units jrc_contact_center_audio_folders].each do |table|
        connection.execute("INSERT INTO #{table} SELECT * FROM public.#{table}")
      end
      before = connection.select_one("SELECT * FROM jrc_contact_center_units WHERE id = #{unit.id}")
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_audio_versions').to_i).to eq(0)
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_audio_assets').to_i).to eq(0)
      expect(connection.select_one("SELECT * FROM jrc_contact_center_units WHERE id = #{unit.id}")).to eq(before)
      expect(connection.select_value("SELECT name FROM jrc_contact_center_audio_folders WHERE id = #{folder.id}")).to eq(folder.name)
      described_class.new.up
    end
    expect(unit.reload.name).to eq('SYNTHETIC populated audio unit')
  end

  it 'verifies actual fresh or reloaded function/trigger definitions and both tables without duplicating their schema' do
    count = JrcContactCenter::AudioVersion.count
    described_class.new.up
    described_class.new.up
    expect(JrcContactCenter::AudioVersion.count).to eq(count)
    expect(ActiveRecord::Base.connection.foreign_keys(:jrc_contact_center_audio_versions).length).to eq(4)
    index = ActiveRecord::Base.connection.indexes(:jrc_contact_center_audio_versions).find { |row| row.name == 'cc_audio_version_blob' }
    expect(index.unique).to be(true)
  end

  it 'refuses a partial table instead of silently stamping or repairing unknown data' do
    in_owned_preupgrade_schema do |connection|
      connection.create_table(:jrc_contact_center_audio_assets) { |table| table.string :unreviewed }
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio file schema/)
    end
  end

  it 'preserves the exact CR/LF filename restriction without embedding control bytes in schema SQL' do
    connection = ActiveRecord::Base.connection
    constraint = connection.check_constraints(:jrc_contact_center_audio_versions).find { |row| row.name == 'cc_audio_version_filename' }
    expect(constraint.expression).not_to match(/[\r\n]/)
    expect(constraint.expression).to include('chr(13)', 'chr(10)')
    names = ['SYNTHETIC.wav', "SYNTHETIC\r.wav", "SYNTHETIC\n.wav", "SYNTHETIC\r\n.wav", '']
    values = names.map { |name| "(#{connection.quote(name)})" }.join(', ')
    accepted = connection.select_values("SELECT file_name FROM (VALUES #{values}) AS files(file_name) WHERE #{constraint.expression}")
    expect(accepted).to eq(['SYNTHETIC.wav'])
  end

  it 'keeps all and only the exact source/type pairs without unstable varchar-array coercions' do
    connection = ActiveRecord::Base.connection
    constraint = connection.check_constraints(:jrc_contact_center_audio_versions).find { |row| row.name == 'cc_audio_version_type' }
    expect(constraint.expression).not_to include('character varying', '::text[]')
    sources = %w[user_upload browser_capture forged]
    types = %w[audio/mpeg audio/wav audio/ogg audio/mp4 audio/webm application/pdf audio/WAV]
    values = sources.product(types).map { |source, type| "(#{connection.quote(source)}, #{connection.quote(type)})" }.join(', ')
    accepted = connection.select_rows("SELECT source_kind, content_type FROM (VALUES #{values}) AS files(source_kind, content_type) " \
                                      "WHERE #{constraint.expression}")
    expect(accepted.sort).to eq(sources.first(2).product(types.first(5)).sort)
  end

  it 'detects removal of an exact origin constraint without accepting matching column names as proof' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.remove_foreign_key(:jrc_contact_center_audio_assets, name: 'cc_audio_asset_unit_fk')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio file schema/)
    end
  end

  it 'detects a changed trigger function even if the table, fields, trigger name and source hashes still exist' do
    in_owned_preupgrade_schema do |connection|
      described_class.new.up
      connection.execute('CREATE OR REPLACE FUNCTION cc_institutional_audio_asset_guard() RETURNS trigger ' \
                         'LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END $$')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio file schema/)
    end
  end

  it 'preserves immutable history instead of offering destructive rollback' do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /separately reviewed rollback/)
  end
end
