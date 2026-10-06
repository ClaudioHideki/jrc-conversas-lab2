class AddRelationshipPlaybookConditions < ActiveRecord::Migration[7.1]
  def change
    add_column :jrc_relationship_playbooks, :conditions, :jsonb, null: false, default: []
  end
end
