# frozen_string_literal: true

# Empty optional classification evidence only; no historical qualification or availability is changed.
class CreateContactCenterEndingReasonConfirmations < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_reason_confirmations
  SQL = 'db/functions/20261122212900_contact_center_ending_confirmations.sql'
  SOURCES = {
    SQL => '544a195a90dea477d747c9cd08cf749bebc5d33bc0283c3bc1c11661406be681',
    'lib/jrc_contact_center/ending_confirmation_schema_receipt.rb' => 'cb6c9d0365680e9a64ca88c96240ea0dbe20072f11281f17d2ac7e529cc8438f'
  }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::EndingConfirmationSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    create_records
    indexes
    constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Confirmed classification history requires a separately reviewed rollback'
  end

  private

  def load_sources!
    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Ending confirmation source changed; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/ending_confirmation_schema_receipt')
  end

  def create_records
    create_table TABLE do |table|
      table.references :account, null: false, index: false, foreign_key: { on_delete: :cascade }
      table.bigint :qualification_id
      table.bigint :source_qualification_id, :actor_account_user_id, :actor_user_id, :catalogue_id, null: false
      table.string :request_key, null: false, limit: 120
      table.string :reason_code, null: false, limit: 100
      table.string :reason_label, null: false, limit: 120
      table.string :input_digest, :integrity_sha256, null: false, limit: 64
      table.jsonb :payload, null: false, default: {}
      table.datetime :created_at, null: false
    end
  end

  def indexes
    add_index TABLE, [:account_id, :source_qualification_id], unique: true, name: 'cc_ending_confirmation_source'
    add_index TABLE, [:account_id, :actor_account_user_id, :request_key], unique: true, name: 'cc_ending_confirmation_request'
    add_index TABLE, :qualification_id, unique: true, where: 'qualification_id IS NOT NULL', name: 'cc_ending_confirmation_live'
    add_index TABLE, :catalogue_id, name: 'cc_ending_confirmation_catalogue'
  end

  def constraints
    add_foreign_key TABLE, :jrc_contact_center_qualifications, column: :qualification_id, on_delete: :nullify
    add_foreign_key TABLE, :jrc_contact_center_ending_reason_versions, column: :catalogue_id, on_delete: :cascade
    positive = 'source_qualification_id > 0 AND actor_account_user_id > 0 AND actor_user_id > 0 AND catalogue_id > 0'
    add_check_constraint TABLE, positive, name: 'cc_ending_confirmation_identity'
    hashes = "input_digest ~ '^[0-9a-f]{64}$' AND integrity_sha256 ~ '^[0-9a-f]{64}$'"
    add_check_constraint TABLE, hashes, name: 'cc_ending_confirmation_digests'
    bounded = "jsonb_typeof(payload) = 'object' AND octet_length(payload::text) <= 16384 AND " \
              "octet_length(request_key) BETWEEN 1 AND 120 AND btrim(request_key) <> '' AND request_key !~ '[[:cntrl:]]'"
    add_check_constraint TABLE, bounded, name: 'cc_ending_confirmation_capture'
  end
end
