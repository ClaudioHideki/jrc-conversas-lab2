# frozen_string_literal: true

class AllowJrcCultureAccountScope < ActiveRecord::Migration[7.1]
  def change
    change_column_null :jrc_culture_grants, :unit_id, true
    change_column_null :jrc_culture_audiences, :unit_id, true
    change_column_null :jrc_culture_imports, :unit_id, true

    add_index :jrc_culture_grants, %i[account_id member_key role], unique: true,
              where: 'unit_id IS NULL', name: :idx_culture_account_grant
    add_index :jrc_culture_audiences, :version_id, unique: true,
              where: 'unit_id IS NULL', name: :idx_culture_account_audience
  end
end
