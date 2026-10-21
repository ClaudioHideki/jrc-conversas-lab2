# frozen_string_literal: true

module JrcContactCenterFoundationMigrationHelpers
  def scoped_identity(table, index_name)
    add_index table, %i[account_id id], unique: true, name: index_name
  end

  def scoped_fk(from_table, to_table, column, name:)
    add_foreign_key from_table, to_table, column: [:account_id, column], primary_key: %i[account_id id], name: name
  end
end
