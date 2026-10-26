# frozen_string_literal: true

# Publication receipts coordinate existing engines. No policy is enabled, no
# ticket is rebound and no data is backfilled by this additive migration.
class CoordinateServiceDeskAutomationPublications < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_service_desk_automation_publications do |t|
      t.bigint :account_id, null: false
      t.bigint :unit_id, null: false
      t.bigint :published_by_membership_id, null: false
      t.string :kind, null: false
      t.string :code, null: false
      t.string :name, null: false
      t.text :description, null: false, default: ''
      t.bigint :service_id
      t.integer :version, null: false
      t.boolean :enabled, null: false, default: false
      t.jsonb :definition, null: false
      t.jsonb :native_versions, null: false
      t.string :digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    table = :jrc_service_desk_automation_publications
    add_index table, [:account_id, :unit_id, :kind, :code, :version], unique: true, name: 'jrc_sd_automation_publication_version'
    add_index table, [:account_id, :unit_id, :id], unique: true, name: 'jrc_sd_automation_publication_scope'
    add_check_constraint table, "kind IN ('lifecycle','operational') AND version > 0", name: 'jrc_sd_automation_publication_kind'
    add_foreign_key table, :jrc_service_desk_units, column: [:account_id, :unit_id], primary_key: [:account_id, :id], name: 'jrc_sd_ap_unit'
    add_foreign_key table, :jrc_service_desk_unit_memberships, column: [:account_id, :unit_id, :published_by_membership_id],
                                                          primary_key: [:account_id, :unit_id, :id], name: 'jrc_sd_ap_publisher'
    add_foreign_key table, :jrc_service_desk_services, column: [:account_id, :unit_id, :service_id],
                                                   primary_key: [:account_id, :unit_id, :id], name: 'jrc_sd_ap_service'
  end
end
