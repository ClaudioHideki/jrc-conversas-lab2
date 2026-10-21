# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterInboxCommands < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_event_inbox
    create_commands
    add_scoped_foreign_keys
  end

  private

  def create_event_inbox
    create_table :jrc_contact_center_event_inboxes do |table|
      define_event_inbox_columns(table)
      table.timestamps null: false
    end
    index_event_inbox
  end

  def define_event_inbox_columns(table)
    table.bigint :account_id, null: false
    table.string :provider, null: false
    table.string :external_event_id, null: false
    table.string :event_type, null: false
    table.string :schema_version, null: false
    table.datetime :occurred_at, null: false
    table.datetime :received_at, null: false
    table.string :payload_digest, null: false
    table.boolean :signature_verified, null: false, default: false
    table.string :status, null: false, default: 'pending'
    table.integer :attempts, null: false, default: 0
    table.datetime :processed_at
    table.text :last_error
    table.jsonb :payload, null: false
  end

  def index_event_inbox
    scoped_identity(:jrc_contact_center_event_inboxes, 'jrc_cc_event_inbox_ref')
    add_index :jrc_contact_center_event_inboxes, %i[account_id provider external_event_id], unique: true, name: 'jrc_cc_event_once'
    add_index :jrc_contact_center_event_inboxes, %i[account_id status received_at], name: 'jrc_cc_event_pending'
    add_check_constraint :jrc_contact_center_event_inboxes, "status IN ('pending','processed','failed','ignored')", name: 'jrc_cc_event_status'
  end

  def create_commands
    create_table :jrc_contact_center_commands do |table|
      define_commands_columns(table)
      table.timestamps null: false
    end
    index_commands
  end

  def define_commands_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id
    table.bigint :actor_account_user_id, null: false
    table.string :command_id, null: false
    table.string :action, null: false
    table.string :status, null: false, default: 'requested'
    table.integer :expected_state_version
    table.string :reason_code
    table.datetime :requested_at, null: false
    table.datetime :completed_at
    table.jsonb :parameters, null: false, default: {}
    table.jsonb :response, null: false, default: {}
  end

  def index_commands
    scoped_identity(:jrc_contact_center_commands, 'jrc_cc_commands_ref')
    add_index :jrc_contact_center_commands, %i[account_id command_id], unique: true, name: 'jrc_cc_command_once'
    add_index :jrc_contact_center_commands, %i[account_id status requested_at], name: 'jrc_cc_command_pending'
    add_check_constraint :jrc_contact_center_commands,
                         "status IN ('requested','accepted_by_gateway','confirmed_by_pabx','rejected','unknown')",
                         name: 'jrc_cc_command_status'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_event_inboxes, :accounts
    add_foreign_key :jrc_contact_center_commands, :accounts
    scoped_fk(:jrc_contact_center_commands, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_command_session_fk')
    scoped_fk(:jrc_contact_center_commands, :account_users, :actor_account_user_id, name: 'jrc_cc_command_actor_fk')
  end
end
