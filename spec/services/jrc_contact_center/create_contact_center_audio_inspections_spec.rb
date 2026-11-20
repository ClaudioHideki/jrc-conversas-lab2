require 'rails_helper'
require Rails.root.join('db/migrate/20261120153000_create_contact_center_audio_inspections')

RSpec.describe CreateContactCenterAudioInspections do
  include_context 'with an institutional audio receipt'

  def in_owned_preinspection_schema
    connection = ActiveRecord::Base.connection
    connection.transaction(requires_new: true) do
      connection.execute('CREATE SCHEMA cc_audio_inspection_upgrade_synthetic')
      clone_preinspection_tables(connection)
      previous = connection.schema_search_path
      begin
        connection.schema_search_path = 'cc_audio_inspection_upgrade_synthetic'
        yield connection
      ensure
        connection.schema_search_path = previous
      end
      raise ActiveRecord::Rollback
    end
  end

  def clone_preinspection_tables(connection)
    %w[accounts users account_users active_storage_blobs jrc_contact_center_audio_versions].each do |table|
      connection.execute("CREATE TABLE cc_audio_inspection_upgrade_synthetic.#{table} (LIKE public.#{table} INCLUDING ALL)")
    end
  end

  it 'adds an empty observation domain beside populated exact versions without changing any of the nine preceding schemas' do
    source = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                           .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC upgrade source' }, file: upload, key: key)
    in_owned_preinspection_schema do |connection|
      %w[accounts users account_users active_storage_blobs jrc_contact_center_audio_versions].each do |table|
        connection.execute("INSERT INTO #{table} SELECT * FROM public.#{table}")
      end
      before = connection.select_one("SELECT * FROM jrc_contact_center_audio_versions WHERE id = #{source.id}")
      described_class.new.up
      described_class.new.up
      expect(connection.select_value('SELECT COUNT(*) FROM jrc_contact_center_audio_inspections').to_i).to eq(0)
      expect(connection.select_one("SELECT * FROM jrc_contact_center_audio_versions WHERE id = #{source.id}")).to eq(before)
    end
    expect(source.reload.blob.download).to eq(bytes)
  end

  it 'verifies actual installed or reloaded metadata and retains the preceding exact file-domain receipt' do
    connection = ActiveRecord::Base.connection
    count = JrcContactCenter::AudioInspection.count
    described_class.new.up
    described_class.new.up
    JrcContactCenter::AudioFileSchemaReceipt.new(connection).verify!
    expect(JrcContactCenter::AudioInspection.count).to eq(count)
    expect(connection.foreign_keys(:jrc_contact_center_audio_inspections).length).to eq(4)
  end

  it 'refuses partial tables instead of accepting unknown rows or silently restamping them' do
    in_owned_preinspection_schema do |connection|
      connection.create_table(:jrc_contact_center_audio_inspections) { |table| table.string :unknown }
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio inspection schema/)
    end
  end

  it 'detects a disabled observation trigger even if its original CREATE TRIGGER definition is unchanged' do
    in_owned_preinspection_schema do |connection|
      described_class.new.up
      connection.execute('ALTER TABLE jrc_contact_center_audio_inspections DISABLE TRIGGER cc_institutional_audio_inspection_guard')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio inspection schema/)
    end
  end

  it 'detects an origin foreign-key removal rather than treating matching column names as proof of isolation' do
    in_owned_preinspection_schema do |connection|
      described_class.new.up
      connection.remove_foreign_key(:jrc_contact_center_audio_inspections, name: 'cc_audio_inspection_version_fk')
      expect { described_class.new.up }.to raise_error(ActiveRecord::MigrationError, /Unexpected institutional audio inspection schema/)
    end
  end

  it 'preserves technical history rather than offering destructive rollback' do
    expect { described_class.new.down }.to raise_error(ActiveRecord::IrreversibleMigration, /separately reviewed retention/)
  end
end
