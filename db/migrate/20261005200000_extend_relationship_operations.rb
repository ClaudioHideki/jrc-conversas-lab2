class ExtendRelationshipOperations < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_relationship_configuration_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :configuration, null: false, foreign_key: { to_table: :jrc_relationship_configurations }
      t.references :actor, foreign_key: { to_table: :users }
      t.integer :version, null: false
      t.jsonb :weights, null: false
      t.jsonb :rules, null: false
      t.datetime :created_at, null: false
    end
    add_index :jrc_relationship_configuration_versions, [:configuration_id, :version], unique: true, name: 'rel_config_version'
    change_table :jrc_relationship_actions, bulk: true do |t|
      t.references :operations_queue, foreign_key: { to_table: :jrc_operations_queues }
      t.references :operations_sla_policy, foreign_key: { to_table: :jrc_operations_sla_policies }
      t.datetime :sla_started_at
      t.datetime :first_action_due_at
      t.datetime :first_action_at
      t.datetime :stage_due_at
      t.datetime :sla_due_at
      t.datetime :sla_paused_at
      t.integer :sla_paused_seconds, null: false, default: 0
    end
    add_index :jrc_relationship_actions, [:account_id, :operations_queue_id, :status], name: 'rel_operational_queue'
    add_index :jrc_operations_sla_policies, [:account_id, :operations_queue_id, :scope_kind, :name],
      unique: true, name: 'ops_policy_identity'
  end
end
