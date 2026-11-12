class AddRelationshipActionFollowUp < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_relationship_actions, :next_step, :text
    add_column :jrc_relationship_actions, :return_at, :datetime
    add_column :jrc_relationship_actions, :customer_confirmation, :string, null: false, default: 'pending'
    add_column :jrc_relationship_actions, :customer_feedback, :text
    add_column :jrc_relationship_actions, :customer_confirmed_at, :datetime
    add_reference :jrc_relationship_actions, :customer_confirmed_by, foreign_key: { to_table: :users }, index: false
    add_index :jrc_relationship_actions, [:account_id, :owner_id, :return_at], name: 'rel_action_return_queue',
              where: "status IN ('open', 'in_progress', 'waiting_customer', 'waiting_finance')"
    add_check_constraint :jrc_relationship_actions,
                         "customer_confirmation IN ('pending', 'confirmed', 'unresolved', 'not_applicable')",
                         name: 'rel_action_customer_confirmation'
  end
end
