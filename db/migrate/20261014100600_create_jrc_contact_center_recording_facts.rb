# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterRecordingFacts < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_recording_links
    create_daily_facts
    add_scoped_foreign_keys
  end

  private

  def create_recording_links
    create_table :jrc_contact_center_recording_links do |table|
      define_recording_links_columns(table)
      table.timestamps null: false
    end
    index_recording_links
  end

  def define_recording_links_columns(table)
    table.bigint :account_id, null: false
    table.bigint :call_session_id, null: false
    table.bigint :call_leg_id
    table.string :provider, null: false
    table.string :external_recording_id, null: false
    table.string :status, null: false, default: 'available'
    table.integer :duration_seconds
    table.datetime :recorded_at
    table.datetime :expires_at
    table.jsonb :metadata, null: false, default: {}
  end

  def index_recording_links
    scoped_identity(:jrc_contact_center_recording_links, 'jrc_cc_recordings_ref')
    add_index :jrc_contact_center_recording_links, %i[account_id provider external_recording_id], unique: true, name: 'jrc_cc_recording_once'
    add_check_constraint :jrc_contact_center_recording_links, "status IN ('pending','available','expired','revoked')", name: 'jrc_cc_recording_status'
    add_check_constraint :jrc_contact_center_recording_links, 'duration_seconds IS NULL OR duration_seconds >= 0', name: 'jrc_cc_recording_duration'
  end

  def create_daily_facts
    create_table :jrc_contact_center_daily_facts do |table|
      define_daily_facts_columns(table)
      table.timestamps null: false
    end
    index_daily_facts
  end

  def define_daily_facts_columns(table)
    table.bigint :account_id, null: false
    table.date :fact_date, null: false
    table.bigint :unit_id
    table.bigint :queue_id
    table.bigint :account_user_id
    table.string :direction, null: false, default: 'inbound'
    table.integer :offered_count, null: false, default: 0
    table.integer :answered_count, null: false, default: 0
    table.integer :abandoned_count, null: false, default: 0
    table.integer :transferred_count, null: false, default: 0
    table.integer :fallback_count, null: false, default: 0
    table.bigint :wait_seconds, null: false, default: 0
    table.bigint :talk_seconds, null: false, default: 0
    table.bigint :hold_seconds, null: false, default: 0
    table.bigint :acw_seconds, null: false, default: 0
    table.jsonb :data, null: false, default: {}
  end

  def index_daily_facts
    scoped_identity(:jrc_contact_center_daily_facts, 'jrc_cc_daily_facts_ref')
    add_index :jrc_contact_center_daily_facts,
              %i[account_id fact_date unit_id queue_id account_user_id direction], unique: true,
                                                                                   name: 'jrc_cc_daily_fact_dimension', nulls_not_distinct: true
    add_check_constraint :jrc_contact_center_daily_facts, "direction IN ('inbound','outbound','mixed')", name: 'jrc_cc_daily_fact_direction'
    add_check_constraint :jrc_contact_center_daily_facts,
                         'offered_count >= 0 AND answered_count >= 0 AND abandoned_count >= 0 AND transferred_count >= 0 AND fallback_count >= 0',
                         name: 'jrc_cc_daily_fact_counts'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_recording_links, :accounts
    scoped_fk(:jrc_contact_center_recording_links, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_recording_session_fk')
    scoped_fk(:jrc_contact_center_recording_links, :jrc_contact_center_call_legs, :call_leg_id, name: 'jrc_cc_recording_leg_fk')
    add_foreign_key :jrc_contact_center_daily_facts, :accounts
    scoped_fk(:jrc_contact_center_daily_facts, :jrc_contact_center_units, :unit_id, name: 'jrc_cc_fact_unit_fk')
    scoped_fk(:jrc_contact_center_daily_facts, :jrc_contact_center_queues, :queue_id, name: 'jrc_cc_fact_queue_fk')
    scoped_fk(:jrc_contact_center_daily_facts, :account_users, :account_user_id, name: 'jrc_cc_fact_user_fk')
  end
end
