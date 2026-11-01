class VersionBackofficeFulfillmentFlow < ActiveRecord::Migration[7.1]
  def change
    # Existing requests retain their workflow and audit history.
    add_column :jrc_crm_backoffice_requests, :workflow_version, :integer, null: false, default: 1
    add_check_constraint :jrc_crm_backoffice_requests, 'workflow_version IN (1, 2)', name: 'backoffice_workflow_version'
  end
end
