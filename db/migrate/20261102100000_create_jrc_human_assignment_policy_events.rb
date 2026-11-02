class CreateJrcHumanAssignmentPolicyEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :jrc_human_assignment_policy_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.jsonb :previous_policy, null: false, default: {}
      t.jsonb :next_policy, null: false, default: {}
      t.timestamps
    end
    add_index :jrc_human_assignment_policy_events, [:account_id, :inbox_id, :id], name: 'idx_human_policy_history'
  end
end
