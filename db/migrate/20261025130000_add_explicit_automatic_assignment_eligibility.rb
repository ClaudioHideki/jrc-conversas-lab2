class AddExplicitAutomaticAssignmentEligibility < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :auto_assignment_enabled, :boolean, default: true, null: false
    # Historical conversations intentionally remain NULL. Only a new open event
    # under a configured distribution policy may request automatic assignment.
    add_column :conversations, :auto_assignment_requested_at, :datetime
    add_index :conversations, [:inbox_id, :id], name: 'index_conversations_on_pending_auto_assignment',
              where: 'auto_assignment_requested_at IS NOT NULL AND assignee_id IS NULL AND status = 0'
  end
end
