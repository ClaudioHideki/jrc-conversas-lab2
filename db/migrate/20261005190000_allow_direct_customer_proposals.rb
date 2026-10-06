class AllowDirectCustomerProposals < ActiveRecord::Migration[7.1]
  def change
    change_column_null :jrc_crm_proposals, :deal_id, true
    add_reference :jrc_crm_proposals, :company, foreign_key: { to_table: :companies }
    add_reference :jrc_crm_proposals, :contact, foreign_key: true
  end
end
