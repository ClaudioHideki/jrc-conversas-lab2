# frozen_string_literal: true

# Additive technical history; the preceding nine migrations and their immutable sources remain unchanged.
class CreateContactCenterAudioInspections < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_audio_inspections
  SQL_SOURCES = {
    'lib/jrc_contact_center/audio_inspection_sql.rb' => 'd7a42667936a6dda80a42d63e2e4bfc2a4857fc5fe3712ee0f047f2e6bfbb73f',
    'lib/jrc_contact_center/audio_inspection_schema_receipt.rb' => 'e621100ea31d3e7588289d43c6a45a8aba5a62e9cab9545d3ca79d203a1e74d8'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::AudioInspectionSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    create_table TABLE do |t|
      identity_columns(t)
      observation_columns(t)
      t.datetime :created_at, null: false
    end
    add_indexes
    add_origin_constraints
    add_observation_constraints
    execute JrcContactCenter::AudioInspectionSql.call
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Private audio observations require a separately reviewed retention procedure'
  end

  private

  def load_sources!
    SQL_SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed private audio inspection source' unless expected.match?(/\A[0-9a-f]{64}\z/)
      actual = Digest::SHA256.file(Rails.root.join(path)).hexdigest
      raise ActiveRecord::MigrationError, 'Private audio inspection source changed' unless actual == expected

      require Rails.root.join(path)
    end
  end

  def identity_columns(table)
    table.references :account, null: false, foreign_key: true
    table.bigint :unit_id, null: false
    table.bigint :audio_version_id, null: false
    table.bigint :source_blob_id, null: false
    table.bigint :created_by_id, null: false
    table.integer :attempt, null: false
    table.string :idempotency_key, null: false, limit: 100
    table.string :input_digest, null: false, limit: 64
  end

  def observation_columns(table)
    table.string :expected_sha256, null: false, limit: 64
    table.string :observed_sha256, limit: 64
    table.string :state, null: false, limit: 30
    table.string :probe_state, null: false, limit: 30
    table.string :scanner_adapter, null: false, limit: 50
    table.string :decoder_version, limit: 200
    table.jsonb :metadata, null: false, default: {}
    table.datetime :observed_at, null: false
  end

  def add_indexes
    add_index TABLE, %i[account_id unit_id id], unique: true, name: 'cc_audio_inspection_origin_key'
    add_index TABLE, %i[audio_version_id attempt], unique: true, name: 'cc_audio_inspection_sequence'
    add_index TABLE, %i[account_id unit_id created_by_id idempotency_key], unique: true, name: 'cc_audio_inspection_request'
    add_index TABLE, :source_blob_id, name: 'cc_audio_inspection_blob'
    add_index TABLE, :created_by_id, name: 'cc_audio_inspection_author'
  end

  def add_origin_constraints
    add_foreign_key TABLE, :jrc_contact_center_audio_versions,
                    column: %i[account_id unit_id audio_version_id], primary_key: %i[account_id unit_id id],
                    name: 'cc_audio_inspection_version_fk'
    add_foreign_key TABLE, :active_storage_blobs, column: :source_blob_id, name: 'cc_audio_inspection_blob_fk'
    add_foreign_key TABLE, :users, column: :created_by_id, name: 'cc_audio_inspection_author_fk'
    add_check_constraint TABLE, 'attempt > 0', name: 'cc_audio_inspection_attempt'
    add_check_constraint TABLE, "idempotency_key ~ '^[A-Za-z0-9_-]{16,100}$'", name: 'cc_audio_inspection_idempotency'
    add_check_constraint TABLE, "expected_sha256 ~ '^[0-9a-f]{64}$' AND input_digest ~ '^[0-9a-f]{64}$'", name: 'cc_audio_inspection_sha'
    add_check_constraint TABLE, "observed_sha256 IS NULL OR observed_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_audio_inspection_observed_sha'
  end

  def add_observation_constraints
    add_check_constraint TABLE, "state::text IN ('clean'::text, 'infected'::text, 'unavailable'::text, 'checksum_mismatch'::text)",
                         name: 'cc_audio_inspection_state'
    add_check_constraint TABLE, "probe_state::text IN ('not_run'::text, 'valid'::text, 'invalid'::text, 'unavailable'::text)",
                         name: 'cc_audio_inspection_probe_state'
    add_check_constraint TABLE, "scanner_adapter = 'clamav-instream-v1'", name: 'cc_audio_inspection_adapter'
    add_check_constraint TABLE, "state <> 'clean' OR (observed_sha256 IS NOT NULL AND observed_sha256 = expected_sha256)",
                         name: 'cc_audio_inspection_clean_sha'
    add_check_constraint TABLE, "probe_state = 'not_run' OR state = 'clean'", name: 'cc_audio_inspection_probe_requires_scan'
    # The SQL source must additionally validate all seven exact metadata fields, real decoder identity,
    # native MIME correspondence, actor/version/blob origin and append-only sequence; no client proof accepted.
    add_check_constraint TABLE, "jsonb_typeof(metadata) = 'object'", name: 'cc_audio_inspection_metadata_object'
    add_check_constraint TABLE, "probe_state = 'valid' OR (metadata = '{}'::jsonb AND decoder_version IS NULL)",
                         name: 'cc_audio_inspection_metadata_state'
  end
end
