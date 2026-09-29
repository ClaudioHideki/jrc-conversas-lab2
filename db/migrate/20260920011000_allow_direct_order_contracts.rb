class AllowDirectOrderContracts < ActiveRecord::Migration[7.1]
  def change
    change_column_null :jrc_crm_contracts, :deal_id, true
  end
end
