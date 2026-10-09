class CreateJrcNicoHelpdesk < ActiveRecord::Migration[7.1]
  def change
    create_policies
    constrain_policies
    create_profiles
    constrain_profiles
    create_events
    constrain_events
    create_approvals
    constrain_approvals
    create_reports
    constrain_reports
    create_receipts
    constrain_receipts
    create_controls
    constrain_controls
    create_control_events
    constrain_control_events
  end

  private

  def create_policies
    create_table :jrc_nico_helpdesk_policy_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :account_users }
      t.integer :number, null: false
      t.string :state, null: false, default: 'draft'
      t.boolean :enabled, null: false, default: false
      t.jsonb :definition, null: false, default: {}
      t.string :digest, null: false
      t.datetime :published_at
      t.timestamps
    end
  end

  def constrain_policies
    add_index :jrc_nico_helpdesk_policy_versions, [:account_id, :number], unique: true, name: 'nico_hd_policy_number'
  end

  def create_profiles
    create_table :jrc_nico_helpdesk_ticket_profiles do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :unit_id, null: false
      t.bigint :ticket_id, null: false
      t.references :company, foreign_key: true
      t.string :defect_key
      t.string :case_kind
      t.jsonb :evidence, null: false, default: {}
      t.datetime :last_relevant_at
      t.boolean :recurrent, null: false, default: false
      t.boolean :complaint, null: false, default: false
      t.boolean :legal_risk, null: false, default: false
      t.timestamps
    end
  end

  def constrain_profiles
    add_index :jrc_nico_helpdesk_ticket_profiles, :ticket_id, unique: true, name: 'nico_hd_profile_ticket'
    add_index :jrc_nico_helpdesk_ticket_profiles, [:account_id, :company_id, :defect_key], name: 'nico_hd_defect_scope'
    add_foreign_key :jrc_nico_helpdesk_ticket_profiles, :jrc_service_desk_tickets, column: :ticket_id
    add_foreign_key :jrc_nico_helpdesk_ticket_profiles, :jrc_service_desk_units, column: :unit_id
  end

  def create_events
    create_table :jrc_nico_helpdesk_events do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :policy_version_id, null: false
      t.bigint :ticket_id, null: false
      t.references :actor, null: false, foreign_key: { to_table: :account_users }
      t.string :rule_key, null: false
      t.string :correlation_key, null: false
      t.string :state, null: false, default: 'detected'
      t.string :reason
      t.jsonb :evidence, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.datetime :detected_at, null: false
      t.datetime :completed_at
      t.timestamps
    end
  end

  def constrain_events
    add_foreign_key :jrc_nico_helpdesk_events, :jrc_nico_helpdesk_policy_versions, column: :policy_version_id
    add_foreign_key :jrc_nico_helpdesk_events, :jrc_service_desk_tickets, column: :ticket_id
    add_index :jrc_nico_helpdesk_events, [:account_id, :correlation_key], unique: true, name: 'nico_hd_event_once'
  end

  def create_approvals
    create_table :jrc_nico_helpdesk_approvals do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :event_id, null: false
      t.bigint :command_id, null: false
      t.references :approver, null: false, foreign_key: { to_table: :account_users }
      t.string :state, null: false, default: 'pending'
      t.string :payload_digest, null: false
      t.jsonb :scope, null: false, default: {}
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.datetime :reconciled_at
      t.jsonb :reconciliation, null: false, default: {}
      t.timestamps
    end
  end

  def constrain_approvals
    add_foreign_key :jrc_nico_helpdesk_approvals, :jrc_nico_helpdesk_events, column: :event_id
    add_foreign_key :jrc_nico_helpdesk_approvals, :jrc_nico_commands, column: :command_id
    add_index :jrc_nico_helpdesk_approvals, :command_id, unique: true, name: 'nico_hd_approval_command'
  end

  def create_reports
    create_table :jrc_nico_helpdesk_daily_reports do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :policy_version_id, null: false
      t.references :recipient, null: false, foreign_key: { to_table: :account_users }
      t.date :report_date, null: false
      t.string :scope_digest, null: false
      t.string :timezone, null: false
      t.datetime :cutoff_at, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
  end

  def constrain_reports
    add_foreign_key :jrc_nico_helpdesk_daily_reports, :jrc_nico_helpdesk_policy_versions, column: :policy_version_id
    add_index :jrc_nico_helpdesk_daily_reports, [:account_id, :recipient_id, :report_date, :scope_digest],
              unique: true, name: 'nico_hd_daily_once'
  end

  def create_receipts
    create_table :jrc_nico_helpdesk_delivery_receipts do |t|
      t.references :account, null: false, foreign_key: true
      t.references :recipient, null: false, foreign_key: { to_table: :account_users }
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.string :channel, null: false
      t.string :state, null: false, default: 'pending'
      t.string :reason
      t.string :remote_id
      t.datetime :delivered_at
      t.datetime :attempted_at
      t.timestamps
    end
  end

  def constrain_receipts
    add_index :jrc_nico_helpdesk_delivery_receipts, [:account_id, :recipient_id, :source_type, :source_id, :channel],
              unique: true, name: 'nico_hd_delivery_once'
  end

  def create_controls
    create_table :jrc_nico_helpdesk_policy_controls do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :policy_version_id, null: false
      t.boolean :halted, null: false, default: false
      t.datetime :halted_at
      t.timestamps
    end
  end

  def constrain_controls
    add_foreign_key :jrc_nico_helpdesk_policy_controls, :jrc_nico_helpdesk_policy_versions, column: :policy_version_id
    add_index :jrc_nico_helpdesk_policy_controls, [:account_id, :policy_version_id], unique: true, name: 'nico_hd_control_once'
  end

  def create_control_events
    create_table :jrc_nico_helpdesk_control_events do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :policy_version_id, null: false
      t.references :actor, null: false, foreign_key: { to_table: :account_users }
      t.string :action, null: false
      t.string :request_key, null: false
      t.text :reason, null: false
      t.datetime :occurred_at, null: false
      t.timestamps
    end
  end

  def constrain_control_events
    add_foreign_key :jrc_nico_helpdesk_control_events, :jrc_nico_helpdesk_policy_versions, column: :policy_version_id
    add_index :jrc_nico_helpdesk_control_events, [:account_id, :policy_version_id, :actor_id, :request_key], unique: true,
                                                                                                             name: 'nico_hd_control_audit_once'
  end
end
