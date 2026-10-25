class AddDisplayFieldsToSdNotificationVersions < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_service_desk_notification_policy_versions, :display_name, :string, limit: 255
    add_column :jrc_service_desk_notification_policy_versions, :description, :text
  end
end
