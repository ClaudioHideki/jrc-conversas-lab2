class CreateJrcOperatorIntegration < ActiveRecord::Migration[7.1]
  def change
    create_bindings
    create_operations
  end

  private

  def create_bindings
    create_table :jrc_operator_bindings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.bigint :company_id, null: false
      t.bigint :business_unit_id, null: false
      t.string :bemtevi_customer_id, null: false
      t.bigint :allowed_inbox_ids, array: true, null: false, default: []
      t.boolean :active, null: false, default: false
      t.timestamps
    end
    add_foreign_key :jrc_operator_bindings, :companies, column: :company_id
    add_foreign_key :jrc_operator_bindings, :jrc_crm_business_units, column: :business_unit_id
    add_index :jrc_operator_bindings, [:account_id, :contact_id, :business_unit_id], unique: true, name: 'idx_operator_binding_scope'
  end

  def create_operations
    create_table :jrc_operator_operations do |t|
      t.references :binding, null: false, foreign_key: { to_table: :jrc_operator_bindings }
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :key, null: false
      t.jsonb :request_data, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.string :state, null: false, default: 'pending'
      t.bigint :prepared_operation_id
      t.references :conversation, foreign_key: true
      t.references :message, foreign_key: true
      t.timestamps
    end
    add_index :jrc_operator_operations, [:binding_id, :key], unique: true
    add_foreign_key :jrc_operator_operations, :jrc_operator_operations, column: :prepared_operation_id
    add_index :jrc_operator_operations, [:prepared_operation_id, :conversation_id], unique: true, where: "kind = 'send_boleto'",
                                                                                    name: 'idx_operator_boleto_delivery'
  end
end
