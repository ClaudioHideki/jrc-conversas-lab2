class CreateJrcFlowOwnership < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_flow_ownership_scopes do |t|
      t.string :scope_key, null: false
      t.string :host_origin, null: false
      t.bigint :account_id, null: false
      t.bigint :inbox_id, null: false
      t.bigint :generation, null: false, default: 1
      t.string :state, null: false, default: 'LEGACY'
      t.bigint :current_epoch_id
      t.timestamps
    end
    add_index :jrc_flow_ownership_scopes, :scope_key, unique: true
    add_index :jrc_flow_ownership_scopes, [:host_origin, :account_id, :inbox_id], unique: true, name: 'jrc_ownership_destination_unique'
    add_check_constraint :jrc_flow_ownership_scopes, "generation>0 AND state IN('LEGACY','FENCED')", name: 'jrc_ownership_scope_valid'
    # No Account/Inbox FK: remote scopes refer to the destination host's IDs,
    # never the source connection's Account. Scope tombstones survive deletion.
    create_table :jrc_flow_ownership_epochs do |t|
      t.references :scope, null: false, foreign_key: { to_table: :jrc_flow_ownership_scopes, on_delete: :restrict }
      t.references :registration, null: false, foreign_key: { to_table: :jrc_flow_native_registrations, on_delete: :restrict }
      t.uuid :organization_id, null: false
      t.uuid :integration_id, null: false
      t.uuid :channel_id, null: false
      t.uuid :cutover_id, null: false
      t.integer :cutover_revision, null: false
      t.integer :registration_revision, null: false
      t.bigint :generation, null: false
      t.bigint :expected_owner_revision, null: false
      t.bigint :reopened_owner_revision
      t.string :state, null: false
      t.uuid :lease_token, null: false
      t.datetime :lease_until, null: false
      t.datetime :accepted_at
      t.datetime :retired_at
      t.datetime :reopened_at
      t.timestamps
    end
    add_index :jrc_flow_ownership_epochs, [:scope_id, :cutover_id, :cutover_revision], unique: true, name: 'jrc_ownership_epoch_unique'
    add_check_constraint :jrc_flow_ownership_epochs,
                         'cutover_revision>0 AND registration_revision>0 AND generation>0 AND expected_owner_revision>=0 ' \
                         "AND state IN('FENCED','DRAINED','NOT_STARTED_RETIRED','REOPENED')", name: 'jrc_ownership_epoch_valid'
    create_table :jrc_flow_ownership_executions, id: :uuid do |t|
      t.string :scope_key, null: false
      t.bigint :generation, null: false
      t.string :entrypoint, null: false
      t.string :run_reference, null: false
      t.string :state, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :jrc_flow_ownership_executions, [:scope_key, :generation, :run_reference], name: 'jrc_ownership_execution_scope'
    add_check_constraint :jrc_flow_ownership_executions, "generation>0 AND state IN('RUNNING','QUIESCENT','UNKNOWN')",
                         name: 'jrc_ownership_execution_valid'
    create_table :jrc_flow_ownership_effects, id: :uuid do |t|
      t.string :scope_key, null: false
      t.bigint :generation, null: false
      t.uuid :execution_id, null: false
      t.string :effect_reference, null: false
      t.string :kind, null: false
      t.string :state, null: false
      t.bigint :message_id
      t.timestamps
    end
    add_index :jrc_flow_ownership_effects, [:scope_key, :generation, :effect_reference], unique: true, name: 'jrc_ownership_effect_once'
    add_check_constraint :jrc_flow_ownership_effects,
                         "generation>0 AND kind IN('EXTERNAL','DATABASE','MESSAGE') " \
                         "AND state IN('DISPATCHED','OBSERVED','QUEUED','CONFIRMED','CANCELED','UNKNOWN')", name: 'jrc_ownership_effect_valid'
    # Effect/execution identifiers deliberately have no runner/message FKs.
    # Their independently committed UNKNOWN evidence survives runner rollback,
    # source row purge and after_commit delivery failures.
  end
end
