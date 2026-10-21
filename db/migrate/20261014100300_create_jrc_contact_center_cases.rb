# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterCases < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_cases
    create_case_events
    create_callbacks
    add_scoped_foreign_keys
  end

  private

  def create_cases
    create_table :jrc_contact_center_cases do |table|
      define_cases_columns(table)
      table.timestamps null: false
    end
    index_cases
  end

  def define_cases_columns(table)
    table.bigint :account_id, null: false
    table.string :protocol, null: false
    table.integer :contact_id
    table.bigint :company_id
    table.bigint :call_session_id
    table.bigint :owner_account_user_id
    table.bigint :unit_id
    table.bigint :queue_id
    table.string :channel, null: false, default: 'voice'
    table.string :category, null: false
    table.string :subcategory
    table.string :priority, null: false, default: 'normal'
    table.string :status, null: false, default: 'open'
    table.datetime :due_at
    table.string :summary, null: false
    table.text :details
    table.jsonb :metadata, null: false, default: {}
    table.integer :lock_version, null: false, default: 0
  end

  def index_cases
    scoped_identity(:jrc_contact_center_cases, 'jrc_cc_cases_ref')
    add_index :jrc_contact_center_cases, %i[account_id protocol], unique: true, name: 'jrc_cc_case_protocol'
    add_index :jrc_contact_center_cases, %i[account_id status due_at], name: 'jrc_cc_case_queue'
    add_check_constraint :jrc_contact_center_cases, "priority IN ('low','normal','high','urgent')", name: 'jrc_cc_case_priority'
    add_check_constraint :jrc_contact_center_cases,
                         "status IN ('open','in_progress','waiting','resolved','closed','canceled')", name: 'jrc_cc_case_status'
  end

  def create_case_events
    create_table :jrc_contact_center_case_events do |table|
      define_case_events_columns(table)
      table.timestamps null: false
    end
    index_case_events
  end

  def define_case_events_columns(table)
    table.bigint :account_id, null: false
    table.bigint :case_id, null: false
    table.bigint :actor_account_user_id
    table.string :event_type, null: false
    table.datetime :occurred_at, null: false
    table.jsonb :data, null: false, default: {}
  end

  def index_case_events
    scoped_identity(:jrc_contact_center_case_events, 'jrc_cc_case_events_ref')
    add_index :jrc_contact_center_case_events, %i[account_id case_id occurred_at], name: 'jrc_cc_case_timeline'
  end

  def create_callbacks
    create_table :jrc_contact_center_callbacks do |table|
      define_callbacks_columns(table)
      table.timestamps null: false
    end
    index_callbacks
  end

  def define_callbacks_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id
    table.bigint :case_id
    table.integer :contact_id
    table.bigint :queue_id
    table.bigint :owner_account_user_id
    table.string :target_phone
    table.string :consent_channel
    table.string :idempotency_key, null: false
    table.string :state, null: false, default: 'scheduled'
    table.integer :attempts, null: false, default: 0
    table.datetime :scheduled_at, null: false
    table.datetime :completed_at
    table.jsonb :metadata, null: false, default: {}
  end

  def index_callbacks
    scoped_identity(:jrc_contact_center_callbacks, 'jrc_cc_callbacks_ref')
    add_index :jrc_contact_center_callbacks, %i[account_id idempotency_key], unique: true, name: 'jrc_cc_callback_once'
    add_index :jrc_contact_center_callbacks, %i[account_id state scheduled_at], name: 'jrc_cc_callback_schedule'
    add_check_constraint :jrc_contact_center_callbacks,
                         "state IN ('scheduled','in_progress','completed','failed','canceled')", name: 'jrc_cc_callback_state'
    add_check_constraint :jrc_contact_center_callbacks, 'contact_id IS NOT NULL OR target_phone IS NOT NULL', name: 'jrc_cc_callback_target'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_cases, :accounts
    scoped_fk(:jrc_contact_center_cases, :contacts, :contact_id, name: 'jrc_cc_case_contact_fk')
    scoped_fk(:jrc_contact_center_cases, :companies, :company_id, name: 'jrc_cc_case_company_fk')
    scoped_fk(:jrc_contact_center_cases, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_case_session_fk')
    scoped_fk(:jrc_contact_center_cases, :account_users, :owner_account_user_id, name: 'jrc_cc_case_owner_fk')
    scoped_fk(:jrc_contact_center_cases, :jrc_contact_center_units, :unit_id, name: 'jrc_cc_case_unit_fk')
    scoped_fk(:jrc_contact_center_cases, :jrc_contact_center_queues, :queue_id, name: 'jrc_cc_case_queue_fk')
    add_foreign_key :jrc_contact_center_case_events, :accounts
    scoped_fk(:jrc_contact_center_case_events, :jrc_contact_center_cases, :case_id, name: 'jrc_cc_case_event_case_fk')
    scoped_fk(:jrc_contact_center_case_events, :account_users, :actor_account_user_id, name: 'jrc_cc_case_event_actor_fk')
    add_foreign_key :jrc_contact_center_callbacks, :accounts
    scoped_fk(:jrc_contact_center_callbacks, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_callback_session_fk')
    scoped_fk(:jrc_contact_center_callbacks, :jrc_contact_center_cases, :case_id, name: 'jrc_cc_callback_case_fk')
    scoped_fk(:jrc_contact_center_callbacks, :contacts, :contact_id, name: 'jrc_cc_callback_contact_fk')
    scoped_fk(:jrc_contact_center_callbacks, :jrc_contact_center_queues, :queue_id, name: 'jrc_cc_callback_queue_fk')
    scoped_fk(:jrc_contact_center_callbacks, :account_users, :owner_account_user_id, name: 'jrc_cc_callback_owner_fk')
  end
end
