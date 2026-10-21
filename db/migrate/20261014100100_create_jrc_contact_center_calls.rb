# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterCalls < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_call_sessions
    create_call_legs
    create_ivr_events
    add_scoped_foreign_keys
  end

  private

  def create_call_sessions
    create_table :jrc_contact_center_call_sessions do |table|
      define_call_sessions_columns(table)
      table.timestamps null: false
    end
    index_call_sessions
  end

  def define_call_sessions_columns(table)
    table.bigint :account_id, null: false
    table.string :provider, null: false, default: 'jrc_pabx'
    table.string :external_session_id
    table.string :correlation_id, null: false
    table.string :direction, null: false
    table.string :status, null: false, default: 'created'
    table.string :ani
    table.string :dnis
    table.integer :contact_id
    table.bigint :company_id
    table.bigint :current_unit_id
    table.bigint :current_queue_id
    table.datetime :started_at, null: false
    table.datetime :answered_at
    table.datetime :ended_at
    table.jsonb :metadata, null: false, default: {}
    table.integer :lock_version, null: false, default: 0
  end

  def index_call_sessions
    scoped_identity(:jrc_contact_center_call_sessions, 'jrc_cc_sessions_ref')
    add_index :jrc_contact_center_call_sessions, %i[account_id correlation_id], unique: true, name: 'jrc_cc_session_correlation'
    add_index :jrc_contact_center_call_sessions, %i[account_id provider external_session_id],
              unique: true, where: 'external_session_id IS NOT NULL', name: 'jrc_cc_session_external'
    add_index :jrc_contact_center_call_sessions, %i[account_id status started_at], name: 'jrc_cc_session_live'
    add_check_constraint :jrc_contact_center_call_sessions, "direction IN ('inbound','outbound')", name: 'jrc_cc_session_direction'
    add_check_constraint :jrc_contact_center_call_sessions,
                         "status IN ('created','ringing','queued','connected','held','transferring','ended','failed')",
                         name: 'jrc_cc_session_status'
  end

  def create_call_legs
    create_table :jrc_contact_center_call_legs do |table|
      define_call_legs_columns(table)
      table.timestamps null: false
    end
    index_call_legs
  end

  def define_call_legs_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id, null: false
    table.bigint :parent_leg_id
    table.bigint :queue_id
    table.bigint :account_user_id
    table.string :external_leg_id
    table.string :direction, null: false
    table.string :status, null: false, default: 'created'
    table.datetime :started_at, null: false
    table.datetime :answered_at
    table.datetime :ended_at
    table.jsonb :metadata, null: false, default: {}
  end

  def index_call_legs
    scoped_identity(:jrc_contact_center_call_legs, 'jrc_cc_legs_ref')
    add_index :jrc_contact_center_call_legs, %i[account_id external_leg_id], unique: true,
                                                                             where: 'external_leg_id IS NOT NULL', name: 'jrc_cc_leg_external'
    add_index :jrc_contact_center_call_legs, %i[account_id call_session_id started_at], name: 'jrc_cc_leg_journey'
    add_check_constraint :jrc_contact_center_call_legs, "direction IN ('inbound','outbound','internal')", name: 'jrc_cc_leg_direction'
    add_check_constraint :jrc_contact_center_call_legs,
                         "status IN ('created','ringing','queued','connected','held','transferred','ended','failed')",
                         name: 'jrc_cc_leg_status'
  end

  def create_ivr_events
    create_table :jrc_contact_center_ivr_events do |table|
      define_ivr_events_columns(table)
      table.timestamps null: false
    end
    index_ivr_events
  end

  def define_ivr_events_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id, null: false
    table.string :external_event_id
    table.string :event_type, null: false
    table.string :menu_key
    table.string :option_key
    table.datetime :occurred_at, null: false
    table.jsonb :payload, null: false, default: {}
  end

  def index_ivr_events
    scoped_identity(:jrc_contact_center_ivr_events, 'jrc_cc_ivr_ref')
    add_index :jrc_contact_center_ivr_events, %i[account_id external_event_id], unique: true,
                                                                                where: 'external_event_id IS NOT NULL', name: 'jrc_cc_ivr_external'
    add_index :jrc_contact_center_ivr_events, %i[account_id call_session_id occurred_at], name: 'jrc_cc_ivr_journey'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_call_sessions, :accounts
    scoped_fk(:jrc_contact_center_call_sessions, :contacts, :contact_id, name: 'jrc_cc_session_contact_fk')
    scoped_fk(:jrc_contact_center_call_sessions, :companies, :company_id, name: 'jrc_cc_session_company_fk')
    scoped_fk(:jrc_contact_center_call_sessions, :jrc_contact_center_units, :current_unit_id, name: 'jrc_cc_session_unit_fk')
    scoped_fk(:jrc_contact_center_call_sessions, :jrc_contact_center_queues, :current_queue_id, name: 'jrc_cc_session_queue_fk')
    add_foreign_key :jrc_contact_center_call_legs, :accounts
    scoped_fk(:jrc_contact_center_call_legs, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_leg_session_fk')
    scoped_fk(:jrc_contact_center_call_legs, :jrc_contact_center_call_legs, :parent_leg_id, name: 'jrc_cc_leg_parent_fk')
    scoped_fk(:jrc_contact_center_call_legs, :jrc_contact_center_queues, :queue_id, name: 'jrc_cc_leg_queue_fk')
    scoped_fk(:jrc_contact_center_call_legs, :account_users, :account_user_id, name: 'jrc_cc_leg_user_fk')
    add_foreign_key :jrc_contact_center_ivr_events, :accounts
    scoped_fk(:jrc_contact_center_ivr_events, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_ivr_session_fk')
  end
end
