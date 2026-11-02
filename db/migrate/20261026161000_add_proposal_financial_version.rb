class AddProposalFinancialVersion < ActiveRecord::Migration[7.1]
  def change
    # Existing proposals retain the exact initial-period valuation they published.
    add_column :jrc_crm_proposals, :financial_version, :integer, default: 2, null: false
  end
end
