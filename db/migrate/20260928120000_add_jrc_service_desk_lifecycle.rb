# frozen_string_literal: true

# CP4-D01 only. Historical migrations and schema.rb must not be edited.
class AddJrcServiceDeskLifecycle < ActiveRecord::Migration[7.1]
  TABLES = %i[services lifecycle_policies lifecycle_policy_versions lifecycle_transitions sla_cycles sla_clocks lifecycle_pauses].freeze

  def up
    create_services
    create_policies
    create_transitions
    create_cycles
    create_pauses
    TABLES.each do |suffix|
      add_foreign_key table(suffix), :accounts, column: :account_id
      fk(suffix, :units, :unit_id, [:account_id])
    end
    fk(:lifecycle_policies, :services, :service_id)
    fk(:lifecycle_policy_versions, :lifecycle_policies, :lifecycle_policy_id)
    fk(:lifecycle_policy_versions, :unit_memberships, :actor_membership_id)
    add_foreign_key table(:lifecycle_policies), table(:lifecycle_policy_versions),
      column: %i[account_id unit_id id current_version_id], primary_key: %i[account_id unit_id lifecycle_policy_id id], name: 'jrc_sd_lc_current_version_fk'
    %i[lifecycle_transitions sla_cycles lifecycle_pauses].each do |suffix|
      fk(suffix, :tickets, :ticket_id)
      fk(suffix, :lifecycle_policy_versions, :lifecycle_policy_version_id)
    end
    fk(:lifecycle_transitions, :unit_memberships, :actor_membership_id)
    fk(:lifecycle_transitions, :ticket_statuses, :from_status_id)
    fk(:lifecycle_transitions, :ticket_statuses, :to_status_id)
    fk(:sla_cycles, :sla_snapshots, :sla_snapshot_id, %i[account_id unit_id ticket_id])
    fk(:sla_clocks, :sla_cycles, :sla_cycle_id, %i[account_id unit_id ticket_id])
    fk(:lifecycle_pauses, :sla_cycles, :sla_cycle_id, %i[account_id unit_id ticket_id])
    fk(:lifecycle_pauses, :unit_memberships, :started_by_membership_id)
    fk(:lifecycle_pauses, :unit_memberships, :ended_by_membership_id)
    add_column table(:tickets), :service_id, :bigint
    add_column table(:tickets), :lifecycle_policy_version_id, :bigint
    add_index table(:tickets), %i[account_id unit_id service_id], name: 'jrc_sd_ticket_service'
    add_index table(:tickets), %i[account_id unit_id lifecycle_policy_version_id], name: 'jrc_sd_ticket_lc_version'
    fk(:tickets, :services, :service_id)
    fk(:tickets, :lifecycle_policy_versions, :lifecycle_policy_version_id)
  end

  def down
    populated = TABLES.any? { |suffix| select_value("SELECT EXISTS (SELECT 1 FROM #{quote_table_name(table(suffix))} LIMIT 1)") }
    linked = select_value("SELECT EXISTS (SELECT 1 FROM #{quote_table_name(table(:tickets))} WHERE service_id IS NOT NULL OR lifecycle_policy_version_id IS NOT NULL LIMIT 1)")
    raise ActiveRecord::IrreversibleMigration, 'Lifecycle data exists; no destructive rollback' if populated || linked

    remove_foreign_key table(:tickets), name: fk_name(:tickets, :service_id)
    remove_foreign_key table(:tickets), name: fk_name(:tickets, :lifecycle_policy_version_id)
    remove_column table(:tickets), :service_id
    remove_column table(:tickets), :lifecycle_policy_version_id
    remove_foreign_key table(:lifecycle_policies), name: 'jrc_sd_lc_current_version_fk'
    TABLES.reverse_each { |suffix| drop_table table(suffix) }
  end

  private

  def table(suffix)
    "jrc_service_desk_#{suffix}"
  end

  def scope_columns(t, ticket: false)
    t.integer :account_id, null: false
    t.bigint :unit_id, null: false
    t.bigint :ticket_id, null: false if ticket
  end

  def refs(suffix, ticket: false)
    keys = ticket ? %i[account_id unit_id ticket_id id] : %i[account_id unit_id id]
    add_index table(suffix), keys, unique: true, name: "jrc_sd_lc_#{suffix}_ref"
  end

  def fk_name(source, column)
    # PostgreSQL identifier limit: explicit deterministic short names.
    require 'digest'
    "jrc_sd_lc_#{Digest::SHA256.hexdigest("#{source}/#{column}")[0, 20]}_fk"
  end

  def fk(source, target, column, prefix = %i[account_id unit_id])
    add_foreign_key table(source), table(target), column: prefix + [column], primary_key: prefix + [:id], name: fk_name(source, column)
  end

  def create_services
    create_table table(:services) do |t|
      scope_columns(t)
      t.string :name, null: false, limit: 255
      t.string :code, null: false, limit: 80
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    refs(:services)
    add_index table(:services), %i[account_id unit_id code], unique: true, name: 'jrc_sd_lc_service_code'
    add_check_constraint table(:services), "btrim(name) <> '' AND btrim(code) <> ''", name: 'jrc_sd_lc_service_names'
  end

  def create_policies
    create_table table(:lifecycle_policies) do |t|
      scope_columns(t)
      t.bigint :service_id
      t.string :name, null: false, limit: 255
      t.boolean :enabled, null: false, default: false
      t.bigint :current_version_id
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    refs(:lifecycle_policies)
    add_index table(:lifecycle_policies), %i[account_id unit_id], unique: true, where: 'service_id IS NULL', name: 'jrc_sd_lc_unit_policy'
    add_index table(:lifecycle_policies), %i[account_id unit_id service_id], unique: true, where: 'service_id IS NOT NULL', name: 'jrc_sd_lc_service_policy'
    create_table table(:lifecycle_policy_versions) do |t|
      scope_columns(t)
      t.bigint :lifecycle_policy_id, null: false
      t.bigint :actor_membership_id, null: false
      t.integer :version, null: false
      t.jsonb :definition, null: false
      t.jsonb :status_phases, null: false
      t.jsonb :publication, null: false
      t.string :digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    refs(:lifecycle_policy_versions)
    add_index table(:lifecycle_policy_versions), %i[account_id unit_id lifecycle_policy_id id], unique: true, name: 'jrc_sd_lc_version_parent_ref'
    add_index table(:lifecycle_policy_versions), %i[lifecycle_policy_id version], unique: true, name: 'jrc_sd_lc_version_number'
    add_check_constraint table(:lifecycle_policy_versions), "version > 0 AND jsonb_typeof(definition) = 'object' AND digest ~ '^[a-f0-9]{64}$'", name: 'jrc_sd_lc_version_valid'
  end

  def create_transitions
    create_table table(:lifecycle_transitions) do |t|
      scope_columns(t, ticket: true)
      t.bigint :lifecycle_policy_version_id, null: false
      t.bigint :actor_membership_id, null: false
      t.bigint :from_status_id, null: false
      t.bigint :to_status_id, null: false
      t.string :action, null: false, limit: 32
      t.string :rule_key, null: false, limit: 80
      t.string :request_key, null: false, limit: 120
      t.string :fingerprint, null: false, limit: 64
      t.datetime :occurred_at, null: false
      t.jsonb :payload, null: false
      t.datetime :created_at, null: false
    end
    refs(:lifecycle_transitions, ticket: true)
    add_index table(:lifecycle_transitions), %i[account_id unit_id ticket_id actor_membership_id request_key], unique: true, name: 'jrc_sd_lc_transition_key'
    add_index table(:lifecycle_transitions), %i[account_id unit_id ticket_id occurred_at id], name: 'jrc_sd_lc_transition_timeline'
    add_check_constraint table(:lifecycle_transitions), "action IN ('pause','resume','resolve','close','cancel','reopen','work_status') AND jsonb_typeof(payload) = 'object' AND fingerprint ~ '^[a-f0-9]{64}$' AND btrim(request_key) <> ''", name: 'jrc_sd_lc_transition_valid'
  end

  def create_cycles
    create_table table(:sla_cycles) do |t|
      scope_columns(t, ticket: true)
      t.bigint :lifecycle_policy_version_id, null: false
      t.bigint :sla_snapshot_id, null: false
      t.integer :number, null: false
      t.datetime :started_at, null: false
      t.timestamps
    end
    refs(:sla_cycles, ticket: true)
    add_index table(:sla_cycles), %i[account_id unit_id ticket_id number], unique: true, name: 'jrc_sd_lc_cycle_number'
    add_check_constraint table(:sla_cycles), 'number > 0', name: 'jrc_sd_lc_cycle_number_valid'
    create_table table(:sla_clocks) do |t|
      scope_columns(t, ticket: true)
      t.bigint :sla_cycle_id, null: false
      t.string :kind, null: false, limit: 24
      t.string :state, null: false, limit: 24
      t.bigint :budget_seconds, null: false
      t.decimal :elapsed_seconds, null: false, precision: 20, scale: 6
      t.datetime :anchor_at, null: false
      t.datetime :due_at, null: false
      t.datetime :achieved_at
      t.string :calculator_version, null: false, limit: 100
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    refs(:sla_clocks, ticket: true)
    add_index table(:sla_clocks), %i[account_id unit_id ticket_id sla_cycle_id kind], unique: true, name: 'jrc_sd_lc_clock_kind'
    add_check_constraint table(:sla_clocks), "kind IN ('first_response','resolution') AND state IN ('running','paused','completed','stopped') AND budget_seconds > 0 AND elapsed_seconds >= 0", name: 'jrc_sd_lc_clock_values'
    add_check_constraint table(:sla_clocks), "(state = 'completed') = (achieved_at IS NOT NULL)", name: 'jrc_sd_lc_clock_completion'
  end

  def create_pauses
    create_table table(:lifecycle_pauses) do |t|
      scope_columns(t, ticket: true)
      t.bigint :lifecycle_policy_version_id, null: false
      t.bigint :sla_cycle_id
      t.bigint :started_by_membership_id, null: false
      t.bigint :ended_by_membership_id
      t.string :reason_code, null: false, limit: 80
      t.jsonb :clocks, null: false
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    refs(:lifecycle_pauses, ticket: true)
    add_index table(:lifecycle_pauses), %i[account_id unit_id ticket_id], unique: true, where: 'ended_at IS NULL', name: 'jrc_sd_lc_one_pause'
    add_check_constraint table(:lifecycle_pauses), "jsonb_typeof(clocks) = 'array' AND clocks <@ '[\"first_response\",\"resolution\"]'::jsonb AND ((ended_at IS NULL) = (ended_by_membership_id IS NULL)) AND (ended_at IS NULL OR ended_at >= started_at)", name: 'jrc_sd_lc_pause_period'
  end
end
