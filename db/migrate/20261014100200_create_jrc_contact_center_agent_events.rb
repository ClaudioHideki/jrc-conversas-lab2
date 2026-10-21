# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterAgentEvents < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_agent_state_events
    create_qualifications
    add_scoped_foreign_keys
  end

  private

  def create_agent_state_events
    create_table :jrc_contact_center_agent_state_events do |table|
      define_agent_state_events_columns(table)
      table.timestamps null: false
    end
    index_agent_state_events
  end

  def define_agent_state_events_columns(table)
    table.bigint :account_id, null: false
    table.bigint :account_user_id, null: false
    table.bigint :queue_id
    table.string :external_event_id
    table.string :state, null: false
    table.string :reason_code
    table.string :source, null: false, default: 'jrc_pabx'
    table.datetime :started_at, null: false
    table.datetime :ended_at
    table.jsonb :metadata, null: false, default: {}
  end

  def index_agent_state_events
    scoped_identity(:jrc_contact_center_agent_state_events, 'jrc_cc_agent_states_ref')
    add_index :jrc_contact_center_agent_state_events, %i[account_id external_event_id],
              unique: true, where: 'external_event_id IS NOT NULL', name: 'jrc_cc_agent_state_external'
    add_index :jrc_contact_center_agent_state_events, %i[account_id account_user_id started_at], name: 'jrc_cc_agent_state_history'
    add_check_constraint :jrc_contact_center_agent_state_events,
                         "state IN ('offline','available','busy','ringing','in_call','acw','paused','unavailable')",
                         name: 'jrc_cc_agent_state'
  end

  def create_qualifications
    create_table :jrc_contact_center_qualifications do |table|
      define_qualifications_columns(table)
      table.timestamps null: false
    end
    index_qualifications
  end

  def define_qualifications_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id, null: false
    table.bigint :account_user_id, null: false
    table.string :outcome_code, null: false
    table.string :reason_code
    table.text :notes
    table.jsonb :data, null: false, default: {}
  end

  def index_qualifications
    scoped_identity(:jrc_contact_center_qualifications, 'jrc_cc_qualifications_ref')
    add_index :jrc_contact_center_qualifications, %i[account_id call_session_id account_user_id], unique: true, name: 'jrc_cc_qualification_once'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_agent_state_events, :accounts
    scoped_fk(:jrc_contact_center_agent_state_events, :account_users, :account_user_id, name: 'jrc_cc_agent_state_user_fk')
    scoped_fk(:jrc_contact_center_agent_state_events, :jrc_contact_center_queues, :queue_id, name: 'jrc_cc_agent_state_queue_fk')
    add_foreign_key :jrc_contact_center_qualifications, :accounts
    scoped_fk(:jrc_contact_center_qualifications, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_qualification_session_fk')
    scoped_fk(:jrc_contact_center_qualifications, :account_users, :account_user_id, name: 'jrc_cc_qualification_user_fk')
  end
end
