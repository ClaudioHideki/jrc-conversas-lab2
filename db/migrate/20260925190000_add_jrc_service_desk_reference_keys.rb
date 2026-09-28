# frozen_string_literal: true

# Only auxiliary unique indexes on native tables; no native data/columns changed.
# PostgreSQL requires these keys for Account-preserving composite foreign keys.
class AddJrcServiceDeskReferenceKeys < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  TABLES = %i[account_users contacts teams conversations].freeze

  def up
    TABLES.each do |table|
      name = "jrc_sd_ref_#{table}"
      next if valid_reference_index?(table, name)

      if index_name_exists?(table, name)
        raise ActiveRecord::MigrationError, "Inspect the existing #{name} before retrying"
      end

      add_index table, %i[account_id id], unique: true, name: name, algorithm: :concurrently
    end
  end

  def down
    TABLES.reverse_each do |table|
      remove_index table, name: "jrc_sd_ref_#{table}", algorithm: :concurrently
    end
  end

  private

  def valid_reference_index?(table, name)
    index = connection.indexes(table).find { |item| item.name == name }
    return false unless index && index.unique && index.columns == %w[account_id id]

    # PostgreSQL may leave an INVALID index after interrupted concurrent creation.
    connection.select_value(<<~SQL) == true
      SELECT indisvalid FROM pg_index
      WHERE indexrelid = #{connection.quote(name)}::regclass
    SQL
  end
end
