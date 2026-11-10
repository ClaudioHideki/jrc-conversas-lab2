class VersionRelationshipEligibilityDecisions < ActiveRecord::Migration[7.1]
  def change
    add_column :account_users, :jrc_relationship_eligibility_version, :bigint, null: false, default: 0
    add_check_constraint :account_users, 'jrc_relationship_eligibility_version >= 0', name: 'account_users_relationship_eligibility_nonnegative'
  end
end
