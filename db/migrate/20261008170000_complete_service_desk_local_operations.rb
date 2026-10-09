# frozen_string_literal: true

require_relative 'support/jrc_service_desk_r3_catalog_schema'
require_relative 'support/jrc_service_desk_r3_operations_schema'

class CompleteServiceDeskLocalOperations < ActiveRecord::Migration[7.1]
  include JrcServiceDeskR3CatalogSchema
  include JrcServiceDeskR3OperationsSchema

  def up
    extend_classification
    extend_catalogue_defaults
    extend_notification_scopes
    extend_operational_work
    create_operational_resources
    create_resource_links
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve catalogue, operational history and resource links; use reviewed forward recovery'
  end

  private

  def r3_unit_fk(table, column, target, suffix)
    add_foreign_key table, target, column: [:account_id, :unit_id, column], primary_key: %i[account_id unit_id id],
                                   name: "jrc_sd_r3_#{suffix}_fk"
  end

  def r3_account_fk(table, column, target, suffix)
    unless index_exists?(target, %i[account_id id], unique: true)
      add_index target, %i[account_id id], unique: true, name: "jrc_sd_r3_#{target}_account_ref"
    end
    add_foreign_key table, target, column: [:account_id, column], primary_key: %i[account_id id], name: "jrc_sd_r3_#{suffix}_fk"
  end
end
