# frozen_string_literal: true

module JrcServiceDeskV2CatalogSchema
  private

  def extend_service_catalog
    add_column :jrc_service_desk_services, :description, :text
    add_column :jrc_service_desk_services, :form_fields, :jsonb, null: false, default: []
    add_column :jrc_service_desk_services, :default_priority_id, :bigint
    add_column :jrc_service_desk_services, :default_queue_id, :bigint
    add_column :jrc_service_desk_services, :approval_required, :boolean, null: false, default: false
    add_column :jrc_service_desk_tickets, :service_fields, :jsonb, null: false, default: {}
    %i[priority queue].each do |kind|
      add_foreign_key :jrc_service_desk_services, "jrc_service_desk_#{kind == :priority ? 'priorities' : 'queues'}",
                      column: [:account_id, :unit_id, "default_#{kind}_id"], primary_key: %i[account_id unit_id id],
                      name: "jrc_sd_service_default_#{kind}_fk"
    end
  end
end
