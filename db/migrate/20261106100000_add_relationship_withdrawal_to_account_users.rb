class AddRelationshipWithdrawalToAccountUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :jrc_relationship_withdrawn_at, :datetime, precision: 6
  end
end
