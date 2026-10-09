class CompleteRelationshipSharedSurveys < ActiveRecord::Migration[7.1]
  def change
    create_survey_definitions
    create_survey_rules
    create_survey_versions
    change_column_null :jrc_relationship_surveys, :assignment_id, true
    extend_surveys
    add_index :jrc_relationship_surveys, [:account_id, :status, :scheduled_at], name: 'rel_survey_dispatch_queue'
    create_survey_dispatch_decisions
    create_handoff_cases
    add_commercial_references
    add_column :jrc_relationship_playbooks, :version, :integer, null: false, default: 1
    create_playbook_versions
    create_playbook_executions
  end

  private

  def create_survey_definitions
    create_table :jrc_relationship_survey_definitions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: 'draft'
      t.integer :version, null: false, default: 1
      t.jsonb :questions, null: false, default: []
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_relationship_survey_definitions, [:account_id, :code], unique: true, name: 'rel_survey_definition_code'
  end

  def create_survey_rules
    create_table :jrc_relationship_survey_rules do |t|
      t.references :account, null: false, foreign_key: true
      t.references :definition, null: false, foreign_key: { to_table: :jrc_relationship_survey_definitions }, index: false
      t.references :execution_member, foreign_key: { to_table: :account_users }, index: false
      t.string :name, null: false
      t.boolean :active, null: false, default: false
      t.integer :version, null: false, default: 1
      t.integer :priority, null: false, default: 0
      t.jsonb :matchers, null: false, default: {}
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
  end

  def create_survey_versions
    create_table :jrc_relationship_survey_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.string :entity_type, null: false
      t.bigint :entity_id, null: false
      t.integer :version, null: false
      t.references :actor, foreign_key: { to_table: :users }
      t.jsonb :payload, null: false
      t.datetime :created_at, null: false
    end
    add_index :jrc_relationship_survey_versions, [:entity_type, :entity_id, :version], unique: true, name: 'rel_survey_version_identity'
  end

  def extend_surveys
    change_table :jrc_relationship_surveys, bulk: true do |t|
      add_survey_origin(t)
      add_survey_payload(t)
    end
    add_index :jrc_relationship_surveys, [:account_id, :source_type, :source_id, :cycle_key, :rule_id, :rule_version],
              unique: true, where: 'source_type IS NOT NULL', name: 'rel_survey_origin_cycle_rule'
  end

  def create_survey_dispatch_decisions
    create_table :jrc_relationship_survey_dispatch_decisions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :survey, foreign_key: { to_table: :jrc_relationship_surveys }, index: false
      t.references :rule, foreign_key: { to_table: :jrc_relationship_survey_rules }, index: false
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.string :cycle_key, null: false
      t.string :evaluation_key, null: false
      t.string :state, null: false
      t.string :reason, null: false
      t.integer :rule_version
      t.datetime :evaluated_at, null: false
      t.timestamps
    end
    add_index :jrc_relationship_survey_dispatch_decisions, [:account_id, :evaluation_key], unique: true, name: 'rel_survey_decision_identity'
  end

  def create_handoff_cases
    create_table :jrc_relationship_handoff_cases do |t|
      t.references :account, null: false, foreign_key: true
      t.references :assignment, null: false, foreign_key: { to_table: :jrc_relationship_assignments }, index: false
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :checklist, null: false, default: {}
      t.text :reason
      t.references :decided_by, foreign_key: { to_table: :users }, index: false
      t.datetime :decided_at
      t.timestamps
    end
    add_index :jrc_relationship_handoff_cases, [:account_id, :source_type, :source_id], unique: true, name: 'rel_handoff_source'
  end

  def create_playbook_versions
    create_table :jrc_relationship_playbook_versions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :playbook, null: false, foreign_key: { to_table: :jrc_relationship_playbooks }, index: false
      t.references :actor, foreign_key: { to_table: :users }
      t.integer :version, null: false
      t.jsonb :payload, null: false
      t.datetime :created_at, null: false
    end
    add_index :jrc_relationship_playbook_versions, [:playbook_id, :version], unique: true, name: 'rel_playbook_version'
  end

  def create_playbook_executions
    create_table :jrc_relationship_playbook_executions do |t|
      add_execution_references(t)
      t.integer :version, null: false
      t.string :execution_key, null: false
      t.string :source_key, null: false
      t.jsonb :snapshot, null: false
      t.jsonb :step_source_keys, null: false, default: []
      t.string :status, null: false, default: 'planned'
      t.timestamps
    end
    add_index :jrc_relationship_playbook_executions, [:account_id, :execution_key], unique: true, name: 'rel_playbook_execution'
  end

  def add_execution_references(table)
    table.references :account, null: false, foreign_key: true
    table.references :assignment, null: false, foreign_key: { to_table: :jrc_relationship_assignments }, index: false
    table.references :playbook, null: false, foreign_key: { to_table: :jrc_relationship_playbooks }, index: false
    table.references :actor, null: false, foreign_key: { to_table: :users }
  end

  def add_survey_origin(table)
    table.references :company, foreign_key: { to_table: :companies }, index: false
    table.references :contact, foreign_key: true, index: false
    table.references :contract, foreign_key: { to_table: :jrc_crm_contracts }, index: false
    table.references :product, foreign_key: { to_table: :jrc_crm_products }, index: false
    table.references :definition, foreign_key: { to_table: :jrc_relationship_survey_definitions }, index: false
    table.references :rule, foreign_key: { to_table: :jrc_relationship_survey_rules }, index: false
    table.references :execution_member, foreign_key: { to_table: :account_users }, index: false
    table.references :team, foreign_key: true, index: false
    table.references :agent, foreign_key: { to_table: :users }, index: false
    table.string :source_type
    table.bigint :source_id
    table.string :cycle_key
    table.integer :rule_version
    table.integer :definition_version
  end

  def add_survey_payload(table)
    table.jsonb :definition_snapshot, null: false, default: {}
    table.jsonb :rule_snapshot, null: false, default: {}
    table.jsonb :answers, null: false, default: {}
    table.string :classification
    table.string :status, null: false, default: 'awaiting'
    table.datetime :scheduled_at
    table.datetime :sent_at
    table.datetime :dispatch_started_at
    table.string :provider_id
    table.datetime :delivered_at
    table.datetime :failed_at
    table.string :failure_code
    table.string :treatment_status, null: false, default: 'untreated'
    table.text :treatment_cause
    table.datetime :treated_at
    table.integer :attempts, null: false, default: 0
  end

  def add_commercial_references
    add_reference :jrc_relationship_success_plans, :contract, foreign_key: { to_table: :jrc_crm_contracts }
    add_reference :jrc_relationship_success_plans, :product, foreign_key: { to_table: :jrc_crm_products }
    add_reference :jrc_relationship_expansion_signals, :source_contract, foreign_key: { to_table: :jrc_crm_contracts }
    add_reference :jrc_relationship_expansion_signals, :source_product, foreign_key: { to_table: :jrc_crm_products }
    add_column :jrc_relationship_qbrs, :meeting_url, :text
    add_column :jrc_relationship_qbrs, :recording_url, :text
    add_column :jrc_relationship_qbrs, :provider, :string, null: false, default: 'external'
    add_reference :jrc_relationship_qbrs, :contact, foreign_key: true
  end
end
