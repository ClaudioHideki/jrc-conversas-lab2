# frozen_string_literal: true

# No policies or clocks are activated/backfilled. Legacy residence clocks retain
# their original budget/calendar; the three measurements apply to new entries.
class VersionServiceDeskQueuePolicies < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_queues, :ola_targets, :jsonb, default: {}, null: false
    add_column :jrc_service_desk_queues, :ola_calendar, :jsonb, default: {}, null: false
    create_table :jrc_service_desk_queue_policy_versions do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :queue_id, null: false
      t.bigint :published_by_membership_id, null: false
      t.integer :version, null: false
      t.jsonb :definition, null: false
      t.string :digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    add_index :jrc_service_desk_queue_policy_versions, [:queue_id, :version], unique: true, name: 'jrc_sd_queue_policy_version_unique'
    add_index :jrc_service_desk_queue_policy_versions, [:account_id, :unit_id, :id], unique: true, name: 'jrc_sd_queue_policy_scope'
    scoped_fk(:jrc_service_desk_queue_policy_versions, :queue_id, :jrc_service_desk_queues, 'queue')
    scoped_fk(:jrc_service_desk_queue_policy_versions, :published_by_membership_id, :jrc_service_desk_unit_memberships, 'publisher')
    add_column :jrc_service_desk_queues, :current_policy_version_id, :bigint
    scoped_fk(:jrc_service_desk_queues, :current_policy_version_id, :jrc_service_desk_queue_policy_versions, 'current')
    add_column :jrc_service_desk_ola_clocks, :kind, :string, null: false, default: 'queue_residence'
    add_column :jrc_service_desk_ola_clocks, :entry_key, :uuid, null: false, default: -> { 'gen_random_uuid()' }
    add_column :jrc_service_desk_ola_clocks, :queue_policy_version_id, :bigint
    add_column :jrc_service_desk_ola_clocks, :calendar_snapshot, :jsonb, null: false, default: {}
    scoped_fk(:jrc_service_desk_ola_clocks, :queue_policy_version_id, :jrc_service_desk_queue_policy_versions, 'clock_version')
    remove_index :jrc_service_desk_ola_clocks, [:account_id, :unit_id, :ticket_id], name: 'jrc_sd_ola_active_unique', unique: true,
                                                                                    where: "state IN ('running','paused')"
    add_index :jrc_service_desk_ola_clocks, [:account_id, :unit_id, :ticket_id, :kind], unique: true,
                                                                                        where: "state IN ('running','paused')", name: 'jrc_sd_ola_active_kind_unique'
    add_check_constraint :jrc_service_desk_ola_clocks, "kind IN ('queue_residence','first_response','update','resolution')", name: 'jrc_sd_ola_kind'
    create_table :jrc_service_desk_automation_drafts do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :account_user_id, null: false
      t.string :kind, null: false
      t.string :code, null: false
      t.jsonb :payload, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_foreign_key :jrc_service_desk_automation_drafts, :accounts
    add_foreign_key :jrc_service_desk_automation_drafts, :jrc_service_desk_units, column: [:account_id, :unit_id], primary_key: [:account_id, :id],
                                                                                  name: 'jrc_sd_draft_unit'
    add_foreign_key :jrc_service_desk_automation_drafts, :account_users, column: [:account_id, :account_user_id], primary_key: [:account_id, :id],
                                                                         name: 'jrc_sd_draft_member'
    add_index :jrc_service_desk_automation_drafts, [:account_id, :unit_id, :account_user_id, :kind, :code], unique: true,
                                                                                                            name: 'jrc_sd_draft_identity'
  end

  private

  def scoped_fk(table, field, target, suffix)
    add_foreign_key table, target, column: [:account_id, :unit_id, field], primary_key: [:account_id, :unit_id, :id], name: "jrc_sd_qpv_#{suffix}_fk"
  end
end
