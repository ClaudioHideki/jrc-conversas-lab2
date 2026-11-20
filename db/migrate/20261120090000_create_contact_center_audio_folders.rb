# frozen_string_literal: true

class CreateContactCenterAudioFolders < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_audio_folders
  COLUMNS = %w[id account_id unit_id parent_id name description lock_version created_at updated_at].freeze

  def up
    return verify_schema! if table_exists?(TABLE)

    create_table TABLE do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :unit_id, null: false
      t.bigint :parent_id
      t.string :name, null: false, limit: 120
      t.text :description
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_folder_constraints
    verify_schema!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Audio folder and reference history require a separately reviewed rollback'
  end

  private

  def add_folder_constraints
    add_index TABLE, [:account_id, :unit_id, :id], unique: true, name: 'cc_audio_folder_origin_key'
    add_index TABLE, 'unit_id, COALESCE(parent_id, 0), lower(name)', unique: true, name: 'cc_audio_folder_sibling_name'
    add_foreign_key TABLE, :jrc_contact_center_units,
                    column: [:account_id, :unit_id], primary_key: [:account_id, :id]
    add_foreign_key TABLE, TABLE, column: [:account_id, :unit_id, :parent_id], primary_key: [:account_id, :unit_id, :id]
    add_check_constraint TABLE, 'parent_id IS NULL OR parent_id <> id', name: 'cc_audio_folder_not_self'
    add_check_constraint TABLE, 'length(btrim(name)) > 0 AND name = btrim(name)', name: 'cc_audio_folder_name'
    add_check_constraint TABLE, 'lock_version >= 0', name: 'cc_audio_folder_revision'
  end

  def verify_schema!
    valid = connection.columns(TABLE).map(&:name).sort == COLUMNS.sort
    valid &&= valid_columns? && valid_foreign_keys? && valid_indexes? && valid_checks?
    raise ActiveRecord::MigrationError, 'Unexpected institutional audio folder schema' unless valid
  end

  def valid_columns?
    columns = connection.columns(TABLE).index_by(&:name)
    required = %w[id account_id unit_id name lock_version created_at updated_at]
    required.none? { |name| columns.fetch(name).null } && columns.fetch('name').limit == 120 &&
      columns.fetch('lock_version').type == :integer && columns.fetch('lock_version').default.to_s == '0' &&
      columns.fetch('parent_id').null && columns.fetch('description').null
  end

  def valid_foreign_keys?
    keys = connection.foreign_keys(TABLE)
    keys.length == 3 && foreign_key?(keys, 'accounts', ['account_id'], ['id'], :cascade) &&
      foreign_key?(keys, 'jrc_contact_center_units', %w[account_id unit_id], %w[account_id id], nil) &&
      foreign_key?(keys, TABLE.to_s, %w[account_id unit_id parent_id], %w[account_id unit_id id], nil)
  end

  def foreign_key?(keys, table, columns, primary, deletion)
    keys.any? do |key|
      key.to_table == table && Array(key.column) == columns && Array(key.primary_key) == primary && key.on_delete == deletion
    end
  end

  def valid_indexes?
    indexes = connection.indexes(TABLE)
    origin = indexes.any? { |row| row.unique && row.columns == %w[account_id unit_id id] }
    sibling = indexes.find { |row| row.name == 'cc_audio_folder_sibling_name' }
    origin && sibling&.unique && normalize(sibling.columns.to_s) == 'unit_id,coalesceparent_id,0,lowername'
  end

  def valid_checks?
    expected = { 'cc_audio_folder_not_self' => 'parent_id IS NULL OR parent_id <> id',
                 'cc_audio_folder_name' => 'length(btrim(name)) > 0 AND name = btrim(name)',
                 'cc_audio_folder_revision' => 'lock_version >= 0' }
    actual = connection.check_constraints(TABLE).to_h { |row| [row.name, normalize(row.expression)] }
    actual == expected.transform_values { |expression| normalize(expression) }
  end

  def normalize(value)
    value.gsub(/::[a-z]+|[()\s"]/, '').downcase
  end
end
