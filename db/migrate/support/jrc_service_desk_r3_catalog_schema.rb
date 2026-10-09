# frozen_string_literal: true

module JrcServiceDeskR3CatalogSchema
  def extend_classification
    create_table :jrc_service_desk_ticket_types do |table|
      table.bigint :account_id, null: false
      table.bigint :unit_id, null: false
      table.string :name, null: false
      table.string :code, limit: 80, null: false
      table.boolean :active, null: false, default: false
      table.jsonb :form_fields, null: false, default: []
      table.timestamps
    end
    add_index :jrc_service_desk_ticket_types, %i[account_id unit_id code], unique: true, name: 'jrc_sd_r3_type_code'
    add_index :jrc_service_desk_ticket_types, %i[account_id unit_id id], unique: true, name: 'jrc_sd_r3_type_scope'
    r3_account_fk(:jrc_service_desk_ticket_types, :unit_id, :jrc_service_desk_units, 'type_unit')
    add_column :jrc_service_desk_categories, :parent_id, :bigint
    add_column :jrc_service_desk_categories, :form_fields, :jsonb, null: false, default: []
    r3_unit_fk(:jrc_service_desk_categories, :parent_id, :jrc_service_desk_categories, 'category_parent')
    add_check_constraint :jrc_service_desk_categories, 'parent_id IS NULL OR parent_id <> id', name: 'jrc_sd_r3_category_not_self'
    extend_ticket_classification
  end

  def extend_ticket_classification
    %i[ticket_type_id subcategory_id contract_id].each { |column| add_column :jrc_service_desk_tickets, column, :bigint }
    add_column :jrc_service_desk_tickets, :catalogue_snapshot, :jsonb, null: false, default: {}
    r3_unit_fk(:jrc_service_desk_tickets, :ticket_type_id, :jrc_service_desk_ticket_types, 'ticket_type')
    r3_unit_fk(:jrc_service_desk_tickets, :subcategory_id, :jrc_service_desk_categories, 'ticket_subcategory')
    r3_account_fk(:jrc_service_desk_tickets, :contract_id, :jrc_crm_contracts, 'ticket_contract')
  end

  def extend_catalogue_defaults
    table = :jrc_service_desk_services
    %i[default_category_id default_ticket_type_id default_assignee_membership_id].each { |column| add_column table, column, :bigint }
    r3_unit_fk(table, :default_category_id, :jrc_service_desk_categories, 'service_category')
    r3_unit_fk(table, :default_ticket_type_id, :jrc_service_desk_ticket_types, 'service_type')
    r3_unit_fk(table, :default_assignee_membership_id, :jrc_service_desk_unit_memberships, 'service_assignee')
    %i[allowed_company_ids allowed_contract_ids].each { |column| add_column table, column, :jsonb, null: false, default: [] }
    add_column table, :portal_history_days, :integer
    add_column table, :portal_access_until, :datetime
    add_check_constraint table, 'portal_history_days IS NULL OR portal_history_days > 0', name: 'jrc_sd_r3_portal_history_positive'
  end

  def extend_notification_scopes
    table = :jrc_service_desk_notification_policy_versions
    add_column table, :ticket_type_id, :bigint
    add_column table, :service_id, :bigint
    r3_unit_fk(table, :ticket_type_id, :jrc_service_desk_ticket_types, 'notification_type')
    r3_unit_fk(table, :service_id, :jrc_service_desk_services, 'notification_service')
    remove_index table, name: 'jrc_sd_notification_policy_version_unique'
    execute <<~SQL.squish
      CREATE UNIQUE INDEX jrc_sd_r3_notification_scoped_version
      ON jrc_service_desk_notification_policy_versions
      (account_id, unit_id, event_type, channel, COALESCE(ticket_type_id, 0), COALESCE(service_id, 0), version)
    SQL
  end
end
