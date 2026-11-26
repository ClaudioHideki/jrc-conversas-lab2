# frozen_string_literal: true

require 'digest'

# Additive empty human-review history. No grants, provider writes, backfill or operational activation.
class CreateContactCenterQualityReviews < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_quality_review_revisions
  SQL = 'db/functions/20261126193000_contact_center_quality_reviews.sql'
  RECEIPT = 'lib/jrc_contact_center/quality_review_schema_receipt.rb'
  SOURCES = {
    SQL => 'c6f65980ef4ce034b19ebcc4974f251249ac935092be01b613621ef0bd84e19b',
    RECEIPT => '1942b7d67ad38232e6525e7ec5eb368b26c4ae5a1c2f4d2463279e8d76220a57'
  }.freeze

  def up
    verify_sources!
    require Rails.root.join(RECEIPT.delete_suffix('.rb'))
    receipt = JrcContactCenter::QualityReviewSchemaReceipt.new(connection)
    return receipt.verify! if table_exists?(TABLE)

    create_history_table
    create_integrity_constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Human review history requires a separately reviewed rollback'
  end

  private

  def verify_sources!
    raise ActiveRecord::MigrationError, 'Unprepared quality review migration' unless SOURCES.keys.sort == [SQL, RECEIPT].sort

    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Unreviewed quality review source' unless Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
  end

  def create_history_table
    create_table TABLE do |table|
      table.bigint :account_id, :recording_id, :call_session_id, :actor_account_user_id, :actor_user_id, null: false
      table.integer :revision, null: false
      table.uuid :request_key, null: false
      table.string :source_sha256, :input_sha256, null: false, limit: 64
      table.jsonb :original_analysis, :reviewed_values, :scope_snapshot, null: false
      table.datetime :created_at, null: false
    end
    add_foreign_key TABLE, :accounts, column: :account_id, on_delete: :cascade, name: 'cc_quality_review_account_fk'
    add_index TABLE, %i[account_id recording_id revision], unique: true, name: 'cc_quality_review_revision'
    add_index TABLE, %i[account_id request_key], unique: true, name: 'cc_quality_review_request'
  end

  def create_integrity_constraints
    fields = %w[account_id recording_id call_session_id actor_account_user_id actor_user_id revision]
    add_check_constraint TABLE, fields.map { |field| "#{field} > 0" }.join(' AND '), name: 'cc_quality_review_identity'
    add_check_constraint TABLE, "source_sha256 ~ '^[0-9a-f]{64}$' AND input_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_quality_review_fingerprints'
    add_check_constraint TABLE, "jsonb_typeof(original_analysis) = 'object' AND jsonb_typeof(reviewed_values) = 'object' AND " \
                                "jsonb_typeof(scope_snapshot) = 'object'",
                         name: 'cc_quality_review_objects'
    add_check_constraint TABLE, "COALESCE(reviewed_values ->> 'classification' IN ('positive', 'neutral', 'negative') AND " \
                                "jsonb_typeof(reviewed_values -> 'justification') = 'string' AND " \
                                "btrim(reviewed_values ->> 'justification') <> '', false)", name: 'cc_quality_review_reason'
    add_check_constraint TABLE, "COALESCE(jsonb_typeof(reviewed_values -> 'adjusted_themes') = 'array' AND " \
                                "jsonb_typeof(reviewed_values -> 'recommendation_ids') = 'array' AND " \
                                "jsonb_typeof(reviewed_values -> 'adjusted_summary') = 'string', false)", name: 'cc_quality_review_content'
  end
end
