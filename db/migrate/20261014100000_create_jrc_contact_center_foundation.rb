# frozen_string_literal: true

require_relative 'jrc_contact_center/foundation_migration_helpers'

class CreateJrcContactCenterFoundation < ActiveRecord::Migration[7.1]
  include JrcContactCenterFoundationMigrationHelpers

  def change
    create_units
    create_queues
    create_queue_memberships
    add_scoped_foreign_keys
  end

  private

  def create_units
    create_table :jrc_contact_center_units do |table|
      define_units_columns(table)
      table.timestamps null: false
    end
    index_units
  end

  def define_units_columns(table)
    table.bigint :account_id, null: false
    table.bigint :parent_unit_id
    table.string :code, null: false
    table.string :name, null: false
    table.string :kind, null: false
    table.string :status, null: false, default: 'active'
    table.string :timezone, null: false, default: 'UTC'
    table.jsonb :settings, null: false, default: {}
  end

  def index_units
    scoped_identity(:jrc_contact_center_units, 'jrc_cc_units_ref')
    add_index :jrc_contact_center_units, %i[account_id code], unique: true, name: 'jrc_cc_units_code'
    add_check_constraint :jrc_contact_center_units, "kind IN ('sac','finance','coe','administrative')", name: 'jrc_cc_units_kind'
    add_check_constraint :jrc_contact_center_units, "status IN ('active','inactive')", name: 'jrc_cc_units_status'
  end

  def create_queues
    create_table :jrc_contact_center_queues do |table|
      define_queues_columns(table)
      table.timestamps null: false
    end
    index_queues
  end

  def define_queues_columns(table)
    table.bigint :account_id, null: false
    table.bigint :unit_id, null: false
    table.string :code, null: false
    table.string :name, null: false
    table.string :external_ref
    table.string :service_kind, null: false, default: 'voice'
    table.string :strategy, null: false, default: 'provider'
    table.string :status, null: false, default: 'active'
    table.integer :max_wait_seconds
    table.datetime :active_from
    table.datetime :active_until
    table.jsonb :settings, null: false, default: {}
  end

  def index_queues
    scoped_identity(:jrc_contact_center_queues, 'jrc_cc_queues_ref')
    add_index :jrc_contact_center_queues, %i[account_id code], unique: true, name: 'jrc_cc_queues_code'
    add_index :jrc_contact_center_queues, %i[account_id external_ref], unique: true, where: 'external_ref IS NOT NULL', name: 'jrc_cc_queues_external'
    add_check_constraint :jrc_contact_center_queues, "status IN ('active','inactive')", name: 'jrc_cc_queues_status'
    add_check_constraint :jrc_contact_center_queues, 'max_wait_seconds IS NULL OR max_wait_seconds > 0', name: 'jrc_cc_queues_wait'
  end

  def create_queue_memberships
    create_table :jrc_contact_center_queue_memberships do |table|
      define_queue_memberships_columns(table)
      table.timestamps null: false
    end
    index_queue_memberships
  end

  def define_queue_memberships_columns(table)
    table.bigint :account_id, null: false
    table.bigint :queue_id, null: false
    table.bigint :account_user_id, null: false
    table.string :role, null: false, default: 'agent'
    table.integer :priority, null: false, default: 100
    table.boolean :active, null: false, default: true
    table.datetime :starts_at
    table.datetime :ends_at
    table.jsonb :settings, null: false, default: {}
  end

  def index_queue_memberships
    scoped_identity(:jrc_contact_center_queue_memberships, 'jrc_cc_memberships_ref')
    add_index :jrc_contact_center_queue_memberships, %i[account_id queue_id account_user_id], unique: true, name: 'jrc_cc_membership_once'
    add_check_constraint :jrc_contact_center_queue_memberships, "role IN ('agent','supervisor')", name: 'jrc_cc_membership_role'
    add_check_constraint :jrc_contact_center_queue_memberships, 'priority > 0', name: 'jrc_cc_membership_priority'
    add_check_constraint :jrc_contact_center_queue_memberships,
                         'ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at', name: 'jrc_cc_membership_window'
  end

  def add_scoped_foreign_keys
    add_foreign_key :jrc_contact_center_units, :accounts
    scoped_fk(:jrc_contact_center_units, :jrc_contact_center_units, :parent_unit_id, name: 'jrc_cc_unit_parent_fk')
    add_foreign_key :jrc_contact_center_queues, :accounts
    scoped_fk(:jrc_contact_center_queues, :jrc_contact_center_units, :unit_id, name: 'jrc_cc_queue_unit_fk')
    add_foreign_key :jrc_contact_center_queue_memberships, :accounts
    scoped_fk(:jrc_contact_center_queue_memberships, :jrc_contact_center_queues, :queue_id, name: 'jrc_cc_membership_queue_fk')
    scoped_fk(:jrc_contact_center_queue_memberships, :account_users, :account_user_id, name: 'jrc_cc_membership_user_fk')
  end
end
