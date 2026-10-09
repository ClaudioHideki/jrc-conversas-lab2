class AllowRevocationOfSharedSurveyExecutor < ActiveRecord::Migration[7.1]
  def up
    %i[jrc_relationship_survey_rules jrc_relationship_surveys].each do |table|
      remove_foreign_key table, :account_users, column: :execution_member_id
      add_foreign_key table, :account_users, column: :execution_member_id, on_delete: :nullify
    end
  end

  def down
    %i[jrc_relationship_survey_rules jrc_relationship_surveys].each do |table|
      remove_foreign_key table, :account_users, column: :execution_member_id
      add_foreign_key table, :account_users, column: :execution_member_id
    end
  end
end
