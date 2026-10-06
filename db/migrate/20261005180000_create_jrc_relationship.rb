class CreateJrcRelationship < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_relationship_assignments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :company, foreign_key: { to_table: :companies }
      t.references :contact, foreign_key: true
      t.references :owner, foreign_key: { to_table: :users }
      t.references :team, foreign_key: true
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.string :status, null: false, default: 'onboarding'
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_check_constraint :jrc_relationship_assignments, 'num_nonnulls(company_id, contact_id) = 1', name: 'rel_one_identity'
    add_index :jrc_relationship_assignments, [:account_id, :company_id], unique: true, where: 'company_id IS NOT NULL', name: 'rel_unique_company'
    add_index :jrc_relationship_assignments, [:account_id, :contact_id], unique: true, where: 'contact_id IS NOT NULL', name: 'rel_unique_contact'
    add_index :jrc_relationship_assignments, [:account_id, :owner_id, :status], name: 'rel_portfolio_owner'

    create_table :jrc_relationship_configurations do |t|
      t.references :account, null: false, foreign_key: true
      t.string :scope_key, null: false, default: 'account'
      t.integer :version, null: false, default: 1
      t.jsonb :weights, null: false, default: {}
      t.jsonb :rules, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_relationship_configurations, [:account_id, :scope_key], unique: true, name: 'rel_config_scope'

    create_table :jrc_relationship_health_snapshots do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assignment, null: false, foreign_key: { to_table: :jrc_relationship_assignments }, index: false
      t.references :viewer, null: false, foreign_key: { to_table: :users }
      t.integer :config_version, null: false
      t.string :config_scope_key, null: false
      t.string :fingerprint, null: false
      t.decimal :score, precision: 5, scale: 2
      t.string :band, null: false
      t.jsonb :factors, null: false, default: []
      t.jsonb :signals, null: false, default: {}
      t.string :access_signature, null: false
      t.datetime :calculated_at, null: false
      t.timestamps
    end
    add_index :jrc_relationship_health_snapshots, [:assignment_id, :viewer_id, :fingerprint], unique: true, name: 'rel_health_idempotency'
    add_index :jrc_relationship_health_snapshots, [:account_id, :assignment_id, :viewer_id, :calculated_at], name: 'rel_health_history'

    create_table :jrc_relationship_actions do |t|
      relationship_columns(t)
      t.string :kind, null: false
      t.string :reason, null: false
      t.string :source_key, null: false
      t.string :status, null: false, default: 'open'
      t.integer :priority, null: false, default: 50
      t.datetime :due_at
      t.references :activity, foreign_key: { to_table: :jrc_crm_activities }
      t.references :completed_by, foreign_key: { to_table: :users }
      t.datetime :completed_at
      t.text :result
      t.jsonb :factors, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_relationship_actions, [:assignment_id, :source_key], unique: true, name: 'rel_action_dedupe'
    add_index :jrc_relationship_actions, [:account_id, :status, :due_at, :priority], name: 'rel_action_queue'

    create_table :jrc_relationship_risk_cases do |t|
      relationship_columns(t)
      t.string :kind, null: false, default: 'manual'
      t.string :severity, null: false, default: 'high'
      t.string :status, null: false, default: 'detected'
      t.text :reason, null: false
      t.string :source_key, null: false
      t.datetime :due_at
      t.text :outcome
      t.jsonb :plan, null: false, default: {}
      t.datetime :closed_at
      t.timestamps
    end
    add_index :jrc_relationship_risk_cases, [:assignment_id, :source_key], unique: true, name: 'rel_risk_dedupe'

    create_table :jrc_relationship_success_plans do |t|
      relationship_columns(t)
      t.string :title, null: false
      t.string :status, null: false, default: 'active'
      t.date :target_on
      t.jsonb :goals, null: false, default: []
      t.references :project, foreign_key: { to_table: :jrc_projects_projects }
      t.timestamps
    end

    create_table :jrc_relationship_qbrs do |t|
      relationship_columns(t)
      t.string :title, null: false
      t.string :status, null: false, default: 'scheduled'
      t.datetime :scheduled_at, null: false
      t.text :agenda
      t.text :summary
      t.jsonb :participants, null: false, default: []
      t.jsonb :decisions, null: false, default: []
      t.references :activity, foreign_key: { to_table: :jrc_crm_activities }
      t.timestamps
    end

    create_table :jrc_relationship_renewals do |t|
      relationship_columns(t)
      t.references :contract, null: false, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :deal, foreign_key: { to_table: :jrc_crm_deals }
      t.date :renewal_on, null: false
      t.string :status, null: false, default: 'open'
      t.bigint :proposed_mrr_cents
      t.timestamps
    end
    add_index :jrc_relationship_renewals, [:contract_id, :renewal_on], unique: true, name: 'rel_renewal_dedupe'

    create_table :jrc_relationship_expansion_signals do |t|
      relationship_columns(t)
      t.string :title, null: false
      t.string :status, null: false, default: 'suggested'
      t.references :product, foreign_key: { to_table: :jrc_crm_products }
      t.references :deal, foreign_key: { to_table: :jrc_crm_deals }
      t.bigint :potential_cents, null: false, default: 0
      t.text :evidence
      t.timestamps
    end

    create_table :jrc_relationship_surveys do |t|
      relationship_columns(t)
      t.string :kind, null: false, default: 'nps'
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :responded_at
      t.integer :score
      t.text :comment
      t.timestamps
    end
    add_index :jrc_relationship_surveys, :token_digest, unique: true

    create_table :jrc_relationship_playbooks do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :trigger_kind, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :steps, null: false, default: []
      t.timestamps
    end
  end

  private

  def relationship_columns(table)
    table.references :account, null: false, foreign_key: true
    table.references :assignment, null: false, foreign_key: { to_table: :jrc_relationship_assignments }, index: false
    table.references :owner, foreign_key: { to_table: :users }
    table.jsonb :metadata, null: false, default: {}
    table.integer :lock_version, null: false, default: 0
    table.index [:account_id, :assignment_id], name: "#{table.name.delete_prefix('jrc_relationship_')}_rel_scope"
  end
end
