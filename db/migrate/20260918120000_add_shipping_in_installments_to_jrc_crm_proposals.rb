class AddShippingInInstallmentsToJrcCrmProposals < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_crm_proposals, :shipping_in_installments, :boolean, null: false, default: true
  end
end
