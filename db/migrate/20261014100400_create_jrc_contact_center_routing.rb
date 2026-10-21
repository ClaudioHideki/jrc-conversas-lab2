# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterRouting < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_routing_rules
    create_fallback_events
    add_scoped_foreign_keys
  end

  private

  def create_routing_rules
    create_table :jrc_contact_center_routing_rules do |table|
      define_routing_rules_columns(table)
      table.timestamps null: false
    end
    index_routing_rules
  end

  def define_routing_rules_columns(table)
    table.bigint :account_id, null: false
    table.integer :version, null: false
    table.string :rule_key, null: false
    table.string :kind, null: false
    table.string :source_value
    table.bigint :target_unit_id
    table.bigint :target_queue_id
    table.integer :priority, null: false, default: 100
    table.string :state, null: false, default: 'draft'
    table.datetime :starts_at
    table.datetime :ends_at
    table.bigint :created_by_account_user_id, null: false
    table.jsonb :conditions, null: false, default: {}
  end

  def index_routing_rules
    scoped_identity(:jrc_contact_center_routing_rules, 'jrc_cc_routing_ref')
    add_index :jrc_contact_center_routing_rules, %i[account_id version rule_key], unique: true, name: 'jrc_cc_routing_version'
    add_index :jrc_contact_center_routing_rules, %i[account_id state priority], name: 'jrc_cc_routing_active'
    add_check_constraint :jrc_contact_center_routing_rules, "kind IN ('ddd','customer','portfolio','service','fallback')", name: 'jrc_cc_routing_kind'
    add_check_constraint :jrc_contact_center_routing_rules, "state IN ('draft','published','retired')", name: 'jrc_cc_routing_state'
    add_check_constraint :jrc_contact_center_routing_rules, 'target_unit_id IS NOT NULL OR target_queue_id IS NOT NULL', name: 'jrc_cc_routing_target'
    add_check_constraint :jrc_contact_center_routing_rules,
                         'ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at', name: 'jrc_cc_routing_window'
  end

  def create_fallback_events
    create_table :jrc_contact_center_fallback_events do |table|
      define_fallback_events_columns(table)
      table.timestamps null: false
    end
    index_fallback_events
  end

  def define_fallback_events_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id, null: false
    table.bigint :source_unit_id
    table.bigint :source_queue_id
    table.bigint :target_queue_id
    table.string :reason_code, null: false
    table.string :result, null: false, default: 'requested'
    table.boolean :terminal, null: false, default: false
    table.datetime :occurred_at, null: false
    table.jsonb :metadata, null: false, default: {}
  end

  def index_fallback_events
    scoped_identity(:jrc_contact_center_fallback_events, 'jrc_cc_fallback_ref')
    add_index :jrc_contact_center_fallback_events, %i[account_id call_session_id occurred_at], name: 'jrc_cc_fallback_journey'
    add_check_constraint :jrc_contact_center_fallback_events,
                         "result IN ('requested','confirmed','rejected','failed','terminal')", name: 'jrc_cc_fallback_result'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_routing_rules, :accounts
    scoped_fk(:jrc_contact_center_routing_rules, :jrc_contact_center_units, :target_unit_id, name: 'jrc_cc_routing_unit_fk')
    scoped_fk(:jrc_contact_center_routing_rules, :jrc_contact_center_queues, :target_queue_id, name: 'jrc_cc_routing_queue_fk')
    scoped_fk(:jrc_contact_center_routing_rules, :account_users, :created_by_account_user_id, name: 'jrc_cc_routing_actor_fk')
    add_foreign_key :jrc_contact_center_fallback_events, :accounts
    scoped_fk(:jrc_contact_center_fallback_events, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_fallback_session_fk')
    scoped_fk(:jrc_contact_center_fallback_events, :jrc_contact_center_units, :source_unit_id, name: 'jrc_cc_fallback_unit_fk')
    scoped_fk(:jrc_contact_center_fallback_events, :jrc_contact_center_queues, :source_queue_id, name: 'jrc_cc_fallback_source_queue_fk')
    scoped_fk(:jrc_contact_center_fallback_events, :jrc_contact_center_queues, :target_queue_id, name: 'jrc_cc_fallback_target_queue_fk')
  end
end
