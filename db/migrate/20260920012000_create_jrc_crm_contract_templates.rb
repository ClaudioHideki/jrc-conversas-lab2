class CreateJrcCrmContractTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_crm_contract_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :category
      t.text :description
      t.text :body, null: false
      t.jsonb :variables, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :jrc_crm_contract_templates, %i[account_id name], unique: true
    add_reference :jrc_crm_contracts, :contract_template, foreign_key: { to_table: :jrc_crm_contract_templates }
  end
end
