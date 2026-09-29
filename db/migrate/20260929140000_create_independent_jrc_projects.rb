class CreateIndependentJrcProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_projects_projects do |t|
      t.references :account, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: 'planned'
      t.string :visibility, null: false, default: 'members'
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.date :starts_on
      t.date :due_on
      t.jsonb :settings, null: false, default: {}
      t.jsonb :template_snapshot, null: false, default: {}
      t.datetime :archived_at
      t.timestamps
    end
    add_index :jrc_projects_projects, %i[account_id key], unique: true

    create_table :jrc_projects_project_members do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: 'member'
      t.integer :allocation_percent, null: false, default: 100
      t.timestamps
    end
    add_index :jrc_projects_project_members, %i[project_id user_id], unique: true

    create_table :jrc_projects_project_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :version, null: false, default: 1
      t.jsonb :definition, null: false, default: {}
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :jrc_projects_phases do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.date :starts_on
      t.date :ends_on
      t.timestamps
    end

    create_table :jrc_projects_milestones do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.references :phase, foreign_key: { to_table: :jrc_projects_phases }
      t.string :name, null: false
      t.date :due_on
      t.string :status, null: false, default: 'open'
      t.timestamps
    end

    create_table :jrc_projects_custom_field_definitions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, foreign_key: { to_table: :jrc_projects_projects }
      t.string :name, null: false
      t.string :field_type, null: false
      t.boolean :required, null: false, default: false
      t.jsonb :configuration, null: false, default: {}
      t.timestamps
    end

    create_table :jrc_projects_boards do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.string :name, null: false
      t.timestamps
    end

    create_table :jrc_projects_board_columns do |t|
      t.references :account, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: { to_table: :jrc_projects_boards }
      t.string :name, null: false
      t.string :status_key, null: false
      t.integer :position, null: false, default: 0
      t.integer :wip_limit
      t.timestamps
    end

    create_table :jrc_projects_tasks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.references :board_column, foreign_key: { to_table: :jrc_projects_board_columns }
      t.references :parent, foreign_key: { to_table: :jrc_projects_tasks }
      t.references :assignee, foreign_key: { to_table: :users }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: 'backlog'
      t.string :priority, null: false, default: 'medium'
      t.decimal :position, precision: 20, scale: 10, null: false, default: 0
      t.integer :estimated_minutes, null: false, default: 0
      t.date :starts_on
      t.date :due_on
      t.jsonb :custom_fields, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :jrc_projects_tasks, %i[project_id board_column_id position], name: 'idx_jrc_projects_task_order'

    create_table :jrc_projects_checklist_items do |t|
      t.references :account, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: { to_table: :jrc_projects_tasks }
      t.string :text, null: false
      t.boolean :completed, null: false, default: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :jrc_projects_task_comments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: { to_table: :jrc_projects_tasks }
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    create_table :jrc_projects_task_dependencies do |t|
      t.references :account, null: false, foreign_key: true
      t.references :predecessor, null: false, foreign_key: { to_table: :jrc_projects_tasks }
      t.references :successor, null: false, foreign_key: { to_table: :jrc_projects_tasks }
      t.string :kind, null: false, default: 'finish_to_start'
      t.timestamps
    end
    add_index :jrc_projects_task_dependencies, %i[predecessor_id successor_id], unique: true, name: 'idx_jrc_projects_unique_dependency'

    create_table :jrc_projects_sprints do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.string :name, null: false
      t.string :status, null: false, default: 'planned'
      t.date :starts_on
      t.date :ends_on
      t.timestamps
    end

    create_table :jrc_projects_time_entries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.references :task, foreign_key: { to_table: :jrc_projects_tasks }
      t.references :user, null: false, foreign_key: true
      t.integer :minutes, null: false
      t.date :worked_on, null: false
      t.string :status, null: false, default: 'submitted'
      t.integer :hourly_cost_cents
      t.string :currency, null: false, default: 'BRL'
      t.text :notes
      t.timestamps
    end

    create_table :jrc_projects_capacities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.integer :minutes_per_day, null: false, default: 480
      t.timestamps
    end

    create_table :jrc_projects_budgets do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }, index: { unique: true }
      t.bigint :planned_cents, null: false, default: 0
      t.bigint :committed_cents, null: false, default: 0
      t.bigint :actual_cents, null: false, default: 0
      t.string :currency, null: false, default: 'BRL'
      t.timestamps
    end

    %i[risks issues decisions].each do |resource|
      create_table "jrc_projects_#{resource}" do |t|
        t.references :account, null: false, foreign_key: true
        t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
        t.string :title, null: false
        t.text :description
        t.string :status, null: false, default: 'open'
        t.string :severity
        t.references :owner, foreign_key: { to_table: :users }
        t.jsonb :metadata, null: false, default: {}
        t.timestamps
      end
    end

    create_table :jrc_projects_automation_rules do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, foreign_key: { to_table: :jrc_projects_projects }
      t.string :name, null: false
      t.string :event_name, null: false
      t.jsonb :conditions, null: false, default: {}
      t.jsonb :actions, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :jrc_projects_recurrences do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: { to_table: :jrc_projects_projects }
      t.string :frequency, null: false
      t.integer :interval, null: false, default: 1
      t.jsonb :payload, null: false, default: {}
      t.datetime :next_run_at, null: false
      t.string :last_occurrence_key
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :jrc_projects_audit_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :auditable_type, null: false
      t.bigint :auditable_id, null: false
      t.jsonb :before_data, null: false, default: {}
      t.jsonb :after_data, null: false, default: {}
      t.string :correlation_id
      t.datetime :created_at, null: false
    end
    add_index :jrc_projects_audit_events, %i[auditable_type auditable_id]

    create_table :jrc_projects_outbox_events do |t|
      t.references :account, null: false, foreign_key: true
      t.string :event_name, null: false
      t.string :aggregate_type, null: false
      t.bigint :aggregate_id, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :available_at, null: false
      t.datetime :delivered_at
      t.text :last_error
      t.timestamps
    end
    add_index :jrc_projects_outbox_events, %i[status available_at]
    add_reference :jrc_projects_projects, :contact, foreign_key: true
    add_column :jrc_projects_projects, :idempotency_key, :string
    add_column :jrc_projects_projects, :request_fingerprint, :string
    add_column :jrc_projects_projects, :lock_version, :integer, null: false, default: 0
    add_column :jrc_projects_projects, :acceptance_notes, :text
    add_column :jrc_projects_projects, :completed_at, :datetime
    add_reference :jrc_projects_projects, :accepted_by, foreign_key: { to_table: :users }
    add_index :jrc_projects_projects, [:account_id, :idempotency_key], unique: true, where: 'idempotency_key IS NOT NULL', name: 'idx_jrc_project_request'
    add_column :account_users, :jrc_projects_enabled, :boolean, null: false, default: false
  end
end
