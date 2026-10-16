# Intent is persisted separately from calculated indicators and approval decisions.
# These native item tables have no existing structured commercial intent payload.
class AddCommercialGratuityIntent < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_crm_proposal_items, :commercial_gratuity, :jsonb, null: false, default: {}
    add_column :jrc_crm_deal_products, :commercial_gratuity, :jsonb, null: false, default: {}
  end
end
