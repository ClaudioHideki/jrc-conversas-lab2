# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterCallObservations < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_table :jrc_contact_center_call_observations do |table|
      table.bigint :account_id, null: false
      table.bigint :call_session_id, null: false
      table.bigint :author_user_id
      table.integer :call_version, null: false
      table.text :text, null: false
      table.datetime :created_at, null: false
    end
    add_index :jrc_contact_center_call_observations, %i[account_id call_session_id id], name: 'jrc_cc_observation_page'
    add_index :jrc_contact_center_call_observations, %i[account_id call_session_id call_version], unique: true, name: 'jrc_cc_observation_once'
    add_foreign_key :jrc_contact_center_call_observations, :accounts
    add_foreign_key :jrc_contact_center_call_observations, :users, column: :author_user_id, on_delete: :nullify
    scoped_fk :jrc_contact_center_call_observations, :jrc_contact_center_call_sessions, :call_session_id, name: 'jrc_cc_observation_session_fk'
    add_check_constraint :jrc_contact_center_call_observations, 'char_length(text) <= 1000', name: 'jrc_cc_observation_length'
    add_check_constraint :jrc_contact_center_call_observations, 'call_version >= 0', name: 'jrc_cc_observation_version'
  end
end
