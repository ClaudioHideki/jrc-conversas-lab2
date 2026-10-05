class CreateJrcOperationsRoutingAndSla < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_operations_queues do |t|
      t.references :account, null: false, foreign_key: true
      t.references :operating_company, foreign_key: { to_table: :companies }
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :team, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :assignment_strategy, null: false, default: 'manual'
      t.string :specialty
      t.boolean :active, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_operations_queues, %i[account_id code], unique: true, name: 'idx_jrc_ops_queues_account_code'
    add_index :jrc_operations_queues, %i[account_id active], name: 'idx_jrc_ops_queues_active'

    create_table :jrc_operations_sla_policies do |t|
      t.references :account, null: false, foreign_key: true
      t.references :operations_queue, foreign_key: { to_table: :jrc_operations_queues }
      t.string :name, null: false
      t.string :scope_kind, null: false, default: 'backoffice'
      t.string :request_kind
      t.string :priority
      t.integer :first_action_minutes
      t.integer :stage_minutes
      t.integer :total_minutes
      t.boolean :active, null: false, default: true
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :business_hours, null: false, default: {}
      t.jsonb :pause_statuses, null: false, default: ['waiting_customer']
      t.jsonb :alert_thresholds, null: false, default: [50, 75, 90, 100]
      t.jsonb :escalation, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_operations_sla_policies, %i[account_id scope_kind active], name: 'idx_jrc_ops_sla_scope'

    change_table :jrc_crm_backoffice_requests, bulk: true do |t|
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
    add_index :jrc_crm_backoffice_requests, %i[account_id operations_queue_id status], name: 'idx_jrc_bko_queue_status'
    add_index :jrc_crm_backoffice_requests, %i[account_id sla_due_at], name: 'idx_jrc_bko_sla_due'
  end
end
