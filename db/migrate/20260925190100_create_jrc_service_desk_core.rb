# frozen_string_literal: true

# See docs/jrc_service_desk/CP2_MODELO_DE_DADOS.md, written before this migration.
class CreateJrcServiceDeskCore < ActiveRecord::Migration[7.1]
  PREFIX = 'jrc_service_desk_'
  TABLES = %i[operator_companies units unit_memberships ticket_statuses priorities
              categories queues tickets ticket_events ticket_notes sla_snapshots
              sla_milestones ticket_conversations].freeze

  def up
    create_structure
    create_classifications
    create_tickets
    create_history
    create_sla_records
    create_conversation_links
    add_native_and_scoped_keys
  end

  def down
    # An intermediate checkpoint must not silently erase operational data.
    occupied = TABLES.select do |suffix|
      table = "#{PREFIX}#{suffix}"
      table_exists?(table) && connection.select_value("SELECT EXISTS (SELECT 1 FROM #{connection.quote_table_name(table)})")
    end
    if occupied.any?
      raise ActiveRecord::IrreversibleMigration, 'Service Desk tables contain data; preserve them and review rollback explicitly'
    end

    TABLES.reverse_each { |suffix| drop_table "#{PREFIX}#{suffix}" }
  end

  private

  def table(suffix)
    "#{PREFIX}#{suffix}"
  end

  def account_columns(t)
    t.bigint :account_id, null: false
  end

  def unit_columns(t)
    account_columns(t)
    t.bigint :unit_id, null: false
  end

  def named_columns(t)
    t.string :code, null: false, limit: 80
    t.string :name, null: false, limit: 255
    t.boolean :active, null: false, default: true
    t.integer :lock_version, null: false, default: 0
    t.timestamps
  end

  def named_constraints(suffix)
    add_check_constraint table(suffix), "btrim(code) <> '' AND btrim(name) <> ''", name: "jrc_sd_#{suffix}_names"
  end

  def scoped_reference_key(suffix)
    add_index table(suffix), %i[account_id unit_id id], unique: true, name: "jrc_sd_#{suffix}_scope_ref"
  end

  def account_fk(suffix)
    add_foreign_key table(suffix), :accounts, column: :account_id, name: "jrc_sd_#{suffix}_account_fk"
  end

  def unit_fk(suffix)
    add_foreign_key table(suffix), table(:units), column: %i[account_id unit_id], primary_key: %i[account_id id],
                    name: "jrc_sd_#{suffix}_unit_fk"
  end

  def scoped_fk(from, to, column, label)
    add_foreign_key table(from), table(to), column: [:account_id, :unit_id, column], primary_key: %i[account_id unit_id id],
                    name: "jrc_sd_#{label}_fk"
  end

  def native_fk(from, to, column, label)
    add_foreign_key table(from), to, column: [:account_id, column], primary_key: %i[account_id id], name: "jrc_sd_#{label}_fk"
  end

  def create_structure
    create_table table(:operator_companies) do |t|
      account_columns(t)
      named_columns(t)
    end
    add_index table(:operator_companies), %i[account_id id], unique: true, name: 'jrc_sd_operator_ref'
    add_index table(:operator_companies), %i[account_id code], unique: true, name: 'jrc_sd_operator_code'
    named_constraints(:operator_companies)

    create_table table(:units) do |t|
      account_columns(t)
      t.bigint :operator_company_id, null: false
      named_columns(t)
    end
    add_index table(:units), %i[account_id id], unique: true, name: 'jrc_sd_unit_ref'
    add_index table(:units), %i[account_id operator_company_id code], unique: true, name: 'jrc_sd_unit_code'
    named_constraints(:units)

    create_table table(:unit_memberships) do |t|
      unit_columns(t)
      t.bigint :account_user_id, null: false
      t.boolean :active, null: false, default: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    scoped_reference_key(:unit_memberships)
    add_index table(:unit_memberships), %i[account_id unit_id account_user_id], unique: true, name: 'jrc_sd_membership_unique'
    add_index table(:unit_memberships), %i[account_id account_user_id active unit_id], name: 'jrc_sd_membership_access'
  end

  def create_classifications
    create_table table(:ticket_statuses) do |t|
      unit_columns(t)
      named_columns(t)
      t.string :phase, null: false, limit: 24
      t.integer :position, null: false, default: 0
      t.boolean :initial, null: false, default: false
    end
    add_check_constraint table(:ticket_statuses), "phase IN ('open','waiting','resolved','closed','cancelled')",
                         name: 'jrc_sd_status_phase'
    add_check_constraint table(:ticket_statuses), "NOT initial OR phase = 'open'", name: 'jrc_sd_status_initial_phase'
    add_check_constraint table(:ticket_statuses), 'position >= 0', name: 'jrc_sd_status_position'
    add_index table(:ticket_statuses), %i[account_id unit_id], unique: true, where: 'initial AND active', name: 'jrc_sd_status_initial'

    create_table table(:priorities) do |t|
      unit_columns(t)
      named_columns(t)
      t.integer :position, null: false
    end
    add_check_constraint table(:priorities), 'position >= 0', name: 'jrc_sd_priority_position'

    create_table table(:categories) do |t|
      unit_columns(t)
      named_columns(t)
    end

    create_table table(:queues) do |t|
      unit_columns(t)
      named_columns(t)
      t.bigint :team_id
    end
    add_index table(:queues), %i[account_id team_id], name: 'jrc_sd_queue_team'

    %i[ticket_statuses priorities categories queues].each do |suffix|
      scoped_reference_key(suffix)
      named_constraints(suffix)
      add_index table(suffix), %i[account_id unit_id code], unique: true, name: "jrc_sd_#{suffix}_code"
      add_index table(suffix), %i[account_id unit_id active], name: "jrc_sd_#{suffix}_active"
    end
  end

  def create_tickets
    create_table table(:tickets) do |t|
      unit_columns(t)
      t.string :title, null: false, limit: 255
      t.text :description
      t.integer :requester_id, null: false
      t.bigint :status_id, null: false
      t.bigint :priority_id, null: false
      t.bigint :category_id
      t.bigint :queue_id
      t.bigint :team_id
      t.bigint :assignee_membership_id
      t.bigint :created_by_membership_id, null: false
      t.string :origin_channel, null: false, limit: 80
      t.datetime :opened_at, null: false
      t.string :idempotency_key, null: false, limit: 120
      t.string :request_fingerprint, null: false, limit: 64
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    scoped_reference_key(:tickets)
    add_check_constraint table(:tickets), "btrim(title) <> '' AND btrim(origin_channel) <> '' AND btrim(idempotency_key) <> ''",
                         name: 'jrc_sd_ticket_required_text'
    add_check_constraint table(:tickets), "request_fingerprint ~ '^[a-f0-9]{64}$'", name: 'jrc_sd_ticket_fingerprint'
    add_index table(:tickets), %i[account_id unit_id created_by_membership_id idempotency_key], unique: true,
              name: 'jrc_sd_ticket_idempotency'
    add_index table(:tickets), %i[account_id unit_id created_at id], name: 'jrc_sd_ticket_recent'
    %i[status_id priority_id category_id queue_id assignee_membership_id team_id].each do |column|
      add_index table(:tickets), [:account_id, :unit_id, column, :created_at], name: "jrc_sd_ticket_#{column}"
    end
    add_index table(:tickets), %i[account_id requester_id], name: 'jrc_sd_ticket_requester'
  end

  def create_history
    create_table table(:ticket_events) do |t|
      unit_columns(t)
      t.bigint :ticket_id, null: false
      t.bigint :actor_membership_id, null: false
      t.string :event_type, null: false, limit: 80
      t.jsonb :data, null: false, default: {}
      t.string :correlation_id, limit: 120
      t.datetime :created_at, null: false
    end
    add_check_constraint table(:ticket_events), "jsonb_typeof(data) = 'object' AND btrim(event_type) <> ''", name: 'jrc_sd_event_payload'
    add_index table(:ticket_events), %i[account_id unit_id ticket_id created_at id], name: 'jrc_sd_events_timeline'
    add_index table(:ticket_events), %i[account_id unit_id actor_membership_id], name: 'jrc_sd_event_actor'
    add_index table(:ticket_events), %i[account_id event_type created_at], name: 'jrc_sd_event_type'

    create_table table(:ticket_notes) do |t|
      unit_columns(t)
      t.bigint :ticket_id, null: false
      t.bigint :author_membership_id, null: false
      t.text :body, null: false
      t.string :visibility, null: false, default: 'internal', limit: 16
      t.string :idempotency_key, null: false, limit: 120
      t.string :request_fingerprint, null: false, limit: 64
      t.timestamps
    end
    add_check_constraint table(:ticket_notes), "visibility = 'internal' AND btrim(body) <> ''", name: 'jrc_sd_note_internal'
    add_check_constraint table(:ticket_notes), "btrim(idempotency_key) <> '' AND request_fingerprint ~ '^[a-f0-9]{64}$'", name: 'jrc_sd_note_fingerprint'
    add_index table(:ticket_notes), %i[account_id unit_id ticket_id author_membership_id idempotency_key], unique: true, name: 'jrc_sd_note_idempotency'
    add_index table(:ticket_notes), %i[account_id unit_id ticket_id created_at id], name: 'jrc_sd_notes_timeline'
    add_index table(:ticket_notes), %i[account_id unit_id author_membership_id], name: 'jrc_sd_note_author'
  end

  def create_sla_records
    create_table table(:sla_snapshots) do |t|
      unit_columns(t)
      t.bigint :ticket_id, null: false
      t.integer :version, null: false
      %i[source_system source_reference source_version policy_key policy_version calendar_key calendar_version].each do |column|
        t.string column, null: false, limit: 255
      end
      t.string :calendar_scope, null: false, limit: 24
      t.string :timezone, null: false, limit: 100
      %i[contract_conditions policy_conditions calendar_conditions].each { |column| t.jsonb column, null: false }
      t.datetime :captured_at, null: false
      t.datetime :applied_at, null: false
      t.string :payload_digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    add_index table(:sla_snapshots), %i[account_id unit_id ticket_id version], unique: true, name: 'jrc_sd_snapshot_version'
    add_index table(:sla_snapshots), %i[account_id unit_id ticket_id payload_digest], unique: true, name: 'jrc_sd_snapshot_deduplicate'
    add_index table(:sla_snapshots), %i[account_id unit_id ticket_id id], unique: true, name: 'jrc_sd_snapshot_ref'
    add_check_constraint table(:sla_snapshots), 'version > 0', name: 'jrc_sd_snapshot_version_positive'
    add_check_constraint table(:sla_snapshots), "calendar_scope IN ('account','operator_company','unit')", name: 'jrc_sd_snapshot_scope'
    add_check_constraint table(:sla_snapshots), "payload_digest ~ '^[a-f0-9]{64}$'", name: 'jrc_sd_snapshot_digest'
    %i[contract_conditions policy_conditions calendar_conditions].each do |column|
      add_check_constraint table(:sla_snapshots), "jsonb_typeof(#{column}) = 'object'", name: "jrc_sd_snapshot_#{column}"
    end

    create_table table(:sla_milestones) do |t|
      unit_columns(t)
      t.bigint :ticket_id, null: false
      t.bigint :sla_snapshot_id, null: false
      t.string :kind, null: false, limit: 24
      t.datetime :due_at
      t.datetime :calculated_at
      t.string :calculator_version, limit: 100
      t.datetime :achieved_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index table(:sla_milestones), %i[account_id unit_id sla_snapshot_id kind], unique: true, name: 'jrc_sd_milestone_unique'
    add_index table(:sla_milestones), %i[account_id unit_id ticket_id], name: 'jrc_sd_milestone_ticket'
    add_index table(:sla_milestones), %i[account_id unit_id due_at], name: 'jrc_sd_milestone_due'
    add_check_constraint table(:sla_milestones), "kind IN ('first_response','resolution')", name: 'jrc_sd_milestone_kind'
    add_check_constraint table(:sla_milestones), <<~SQL.squish, name: 'jrc_sd_milestone_calculation'
      (due_at IS NULL AND calculated_at IS NULL AND calculator_version IS NULL) OR
      (due_at IS NOT NULL AND calculated_at IS NOT NULL AND calculator_version IS NOT NULL AND btrim(calculator_version) <> '')
    SQL
  end

  def create_conversation_links
    create_table table(:ticket_conversations) do |t|
      unit_columns(t)
      t.bigint :ticket_id, null: false
      t.integer :conversation_id, null: false
      t.bigint :linked_by_membership_id, null: false
      t.timestamps
    end
    add_index table(:ticket_conversations), %i[account_id unit_id ticket_id conversation_id], unique: true, name: 'jrc_sd_conversation_link_unique'
    add_index table(:ticket_conversations), %i[account_id conversation_id], name: 'jrc_sd_conversation_reverse'
    add_index table(:ticket_conversations), %i[account_id unit_id linked_by_membership_id], name: 'jrc_sd_conversation_actor'
  end

  def add_native_and_scoped_keys
    TABLES.each { |suffix| account_fk(suffix) }
    (TABLES - %i[operator_companies units]).each { |suffix| unit_fk(suffix) }
    add_foreign_key table(:units), table(:operator_companies), column: %i[account_id operator_company_id], primary_key: %i[account_id id],
                    name: 'jrc_sd_unit_operator_fk'
    native_fk(:unit_memberships, :account_users, :account_user_id, 'membership_account_user')
    native_fk(:queues, :teams, :team_id, 'queue_team')
    native_fk(:tickets, :contacts, :requester_id, 'ticket_requester')
    native_fk(:tickets, :teams, :team_id, 'ticket_team')
    { ticket_statuses: :status_id, priorities: :priority_id, categories: :category_id, queues: :queue_id }.each do |target, column|
      scoped_fk(:tickets, target, column, "ticket_#{column}")
    end
    scoped_fk(:tickets, :unit_memberships, :created_by_membership_id, 'ticket_creator')
    scoped_fk(:tickets, :unit_memberships, :assignee_membership_id, 'ticket_assignee')
    %i[ticket_events ticket_notes sla_snapshots sla_milestones ticket_conversations].each do |suffix|
      scoped_fk(suffix, :tickets, :ticket_id, "#{suffix}_ticket")
    end
    scoped_fk(:ticket_events, :unit_memberships, :actor_membership_id, 'event_actor')
    scoped_fk(:ticket_notes, :unit_memberships, :author_membership_id, 'note_author')
    scoped_fk(:ticket_conversations, :unit_memberships, :linked_by_membership_id, 'conversation_actor')
    native_fk(:ticket_conversations, :conversations, :conversation_id, 'link_conversation')
    add_foreign_key table(:sla_milestones), table(:sla_snapshots),
                    column: %i[account_id unit_id ticket_id sla_snapshot_id], primary_key: %i[account_id unit_id ticket_id id],
                    name: 'jrc_sd_milestone_snapshot_fk'
  end
end
