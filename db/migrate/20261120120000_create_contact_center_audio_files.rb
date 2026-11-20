# frozen_string_literal: true

# Additive private receipt domain; historical migrations and native unit tables remain unchanged.
class CreateContactCenterAudioFiles < ActiveRecord::Migration[7.1]
  ASSETS = :jrc_contact_center_audio_assets
  VERSIONS = :jrc_contact_center_audio_versions
  SQL_SOURCES = {
    'lib/jrc_contact_center/audio_file_storage_sql.rb' => '78cd8c6013eb8d7378d49c128b87061e442f282f982c13760cc97baebf4558db',
    'lib/jrc_contact_center/audio_file_origin_sql.rb' => '19aa49167a6748d7c01af16399456d498ecb16b40600e45b151bcb91c1da5001',
    'lib/jrc_contact_center/audio_file_schema_receipt.rb' => 'aab9f70fb0f917504ea843fa34bf73d32f9d11292f41581f104f83198086404c'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::AudioFileSchemaReceipt.new(connection)
    return receipt.verify! if [ASSETS, VERSIONS].any? { |table| table_exists?(table) }

    create_assets
    create_versions
    asset_constraints
    version_constraints
    execute JrcContactCenter::AudioFileStorageSql.call
    execute JrcContactCenter::AudioFileOriginSql.call
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Private audio history and storage references require a separately reviewed rollback'
  end

  private

  def load_sources!
    SQL_SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Institutional audio SQL source changed; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected

      require Rails.root.join(path)
    end
  end

  def create_assets
    create_table ASSETS do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :unit_id, null: false
      t.bigint :folder_id
      t.string :name, null: false, limit: 120
      t.text :description
      t.string :purpose, limit: 160
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index ASSETS, [:account_id, :unit_id, :id], unique: true, name: 'cc_audio_asset_origin_key'
    add_index ASSETS, [:unit_id, :folder_id, :id], name: 'cc_audio_asset_folder_list'
  end

  def create_versions
    create_table VERSIONS do |t|
      version_identity(t)
      t.datetime :created_at, null: false
      version_file(t)
    end
    add_index VERSIONS, [:account_id, :unit_id, :id], unique: true, name: 'cc_audio_version_origin_key'
    add_index VERSIONS, [:audio_asset_id, :number], unique: true, name: 'cc_audio_version_sequence'
    add_index VERSIONS, [:account_id, :unit_id, :created_by_id, :idempotency_key], unique: true, name: 'cc_audio_version_request'
    add_index VERSIONS, :blob_id, unique: true, name: 'cc_audio_version_blob'
    add_index VERSIONS, :created_by_id, name: 'cc_audio_version_author'
  end

  def version_identity(table)
    table.references :account, null: false, foreign_key: true
    table.bigint :unit_id, null: false
    table.bigint :audio_asset_id, null: false
    table.bigint :blob_id, null: false
    table.bigint :created_by_id, null: false
    table.integer :number, null: false
    table.string :source_kind, null: false, limit: 30
    table.string :idempotency_key, null: false, limit: 100
    table.string :input_digest, null: false, limit: 64
  end

  def version_file(table)
    table.string :file_name, null: false, limit: 255
    table.string :content_type, null: false, limit: 100
    table.bigint :byte_size, null: false
    table.string :sha256, null: false, limit: 64
  end

  def asset_constraints
    add_foreign_key ASSETS, :jrc_contact_center_units,
                    column: [:account_id, :unit_id], primary_key: [:account_id, :id], name: 'cc_audio_asset_unit_fk'
    add_foreign_key ASSETS, :jrc_contact_center_audio_folders,
                    column: [:account_id, :unit_id, :folder_id], primary_key: [:account_id, :unit_id, :id], name: 'cc_audio_asset_folder_fk'
    add_check_constraint ASSETS, 'length(btrim(name)) > 0 AND name = btrim(name)', name: 'cc_audio_asset_name'
    add_check_constraint ASSETS, 'lock_version >= 0', name: 'cc_audio_asset_revision'
    add_check_constraint ASSETS, 'description IS NULL OR length(description) <= 1000', name: 'cc_audio_asset_description'
  end

  def version_constraints
    add_foreign_key VERSIONS, ASSETS, column: [:account_id, :unit_id, :audio_asset_id], primary_key: [:account_id, :unit_id, :id],
                                      name: 'cc_audio_version_asset_fk'
    add_foreign_key VERSIONS, :active_storage_blobs, column: :blob_id, name: 'cc_audio_version_blob_fk'
    add_foreign_key VERSIONS, :users, column: :created_by_id, name: 'cc_audio_version_author_fk'
    add_check_constraint VERSIONS, 'number > 0', name: 'cc_audio_version_number'
    add_check_constraint VERSIONS, 'byte_size > 0', name: 'cc_audio_version_size'
    add_check_constraint VERSIONS, "sha256 ~ '^[0-9a-f]{64}$' AND input_digest ~ '^[0-9a-f]{64}$'", name: 'cc_audio_version_sha'
    add_check_constraint VERSIONS, "idempotency_key ~ '^[A-Za-z0-9_-]{16,100}$'", name: 'cc_audio_version_idempotency'
    add_check_constraint VERSIONS, 'length(file_name) > 0 AND position(chr(13) in file_name) = 0 AND position(chr(10) in file_name) = 0',
                         name: 'cc_audio_version_filename'
    add_check_constraint VERSIONS, "source_kind::text IN ('user_upload'::text, 'browser_capture'::text) AND " \
                                   "content_type::text IN ('audio/mpeg'::text, 'audio/wav'::text, 'audio/ogg'::text, " \
                                   "'audio/mp4'::text, 'audio/webm'::text)",
                         name: 'cc_audio_version_type'
  end
end
