# frozen_string_literal: true

# Empty immutable receipts only; no policies, grants, existing request rewrites or production activation.
class CreateContactCenterPauseApprovalEvidence < ActiveRecord::Migration[7.1]
  REVIEWS = :jrc_contact_center_pause_approval_reviews
  SCOPES = :jrc_contact_center_pause_approval_scopes
  SQL = 'db/functions/20261122120000_contact_center_pause_approval_evidence.sql'
  SOURCES = { SQL => '98db0077317bf9a8df0e94a2f403913e022ea1db91d0059f883c474d2a4a19e3',
              'lib/jrc_contact_center/pause_approval_schema_receipt.rb' => '2ff201721493e14ea1090d185177f86180cfa844362b7f3c61a1068c9629e653' }.freeze

  def up
    load_sources!
    receipt = JrcContactCenter::PauseApprovalSchemaReceipt.new(connection)
    return receipt.verify! if [REVIEWS, SCOPES].any? { |table| table_exists?(table) }

    create_reviews
    create_scopes
    constraints
    execute File.read(Rails.root.join(SQL))
    receipt.stamp!
    receipt.verify!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Immutable pause approval evidence requires a separately reviewed rollback'
  end

  private

  def load_sources!
    SOURCES.each do |path, expected|
      raise ActiveRecord::MigrationError, 'Pause approval evidence source changed; preserve history' unless
        Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    require Rails.root.join('lib/jrc_contact_center/pause_approval_schema_receipt')
  end

  def create_reviews
    create_table REVIEWS do |table|
      table.references :account, null: false, foreign_key: { on_delete: :cascade }
      table.bigint :deferred_pause_request_id, :actor_account_user_id, :actor_user_id, null: false
      table.jsonb :payload, null: false
      table.string :context_digest, null: false, limit: 64
      table.datetime :created_at, null: false
    end
    add_index REVIEWS, [:account_id, :id], unique: true, name: 'cc_pause_approval_review_owned'
    add_index REVIEWS, [:account_id, :deferred_pause_request_id], unique: true, name: 'cc_pause_approval_review_parent'
    add_index REVIEWS, [:account_id, :actor_account_user_id, :id], name: 'cc_pause_approval_review_actor'
  end

  def create_scopes
    create_table SCOPES do |table|
      table.references :account, null: false, foreign_key: { on_delete: :cascade }
      table.bigint :review_id, :issuer_company_id, null: false
      table.bigint :business_unit_id
      table.jsonb :unit_ids, null: false
      table.datetime :created_at, null: false
    end
    add_index SCOPES, [:account_id, :review_id, :id], name: 'cc_pause_approval_scope_review'
    add_index SCOPES, 'account_id, review_id, issuer_company_id, COALESCE(business_unit_id, 0)',
              unique: true, name: 'cc_pause_approval_scope_identity'
  end

  def constraints
    add_foreign_key SCOPES, REVIEWS, column: [:account_id, :review_id], primary_key: [:account_id, :id],
                    on_delete: :cascade, name: 'cc_pause_approval_scope_root_fk'
    add_check_constraint REVIEWS, "context_digest ~ '^[0-9a-f]{64}$' AND jsonb_typeof(payload) = 'object'",
                         name: 'cc_pause_approval_review_capture'
    add_check_constraint REVIEWS, 'deferred_pause_request_id > 0 AND actor_account_user_id > 0 AND actor_user_id > 0',
                         name: 'cc_pause_approval_review_identity'
    add_check_constraint SCOPES, 'issuer_company_id > 0 AND (business_unit_id IS NULL OR business_unit_id > 0) ' \
                               "AND jsonb_typeof(unit_ids) = 'array'", name: 'cc_pause_approval_scope_capture'
  end
end
