# frozen_string_literal: true

class CreateContactCenterTeamStates < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_team_states
  COLUMNS = %w[id account_id team_id active lock_version created_at updated_at].freeze

  def up
    return verify_existing_table! if table_exists?(TABLE)

    create_table TABLE do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :team, null: false, index: { unique: true }
      t.boolean :active, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_foreign_key TABLE, :teams, column: [:team_id, :account_id], primary_key: [:id, :account_id], on_delete: :cascade
    add_check_constraint TABLE, 'lock_version >= 0', name: 'cc_team_state_revision_nonnegative'
    verify_existing_table!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Removing team state may reactivate suspended Call Center sources'
  end

  private

  def verify_existing_table!
    valid = connection.columns(TABLE).map(&:name).sort == COLUMNS.sort
    valid &&= valid_constraints? && valid_defaults?
    raise ActiveRecord::MigrationError, 'Unexpected Call Center team state schema' unless valid
  end

  def valid_constraints?
    keys = connection.foreign_keys(TABLE)
    keys.length == 2 && cascade_key?(keys, 'accounts', ['account_id'], ['id']) &&
      cascade_key?(keys, 'teams', %w[team_id account_id], %w[id account_id]) && valid_check_and_index?
  end

  def cascade_key?(keys, table, columns, primary)
    keys.any? do |key|
      key.to_table == table && Array(key.column) == columns && Array(key.primary_key) == primary && key.on_delete == :cascade
    end
  end

  def valid_check_and_index?
    checks = connection.check_constraints(TABLE)
    valid = checks.one? && checks.first.name == 'cc_team_state_revision_nonnegative'
    valid &&= checks.first.expression.delete('()').squish == 'lock_version >= 0'
    valid && connection.indexes(TABLE).any? { |index| index.unique && index.columns == ['team_id'] }
  end

  def valid_defaults?
    columns = connection.columns(TABLE).index_by(&:name)
    default_column?(columns.fetch('active'), :boolean, 'true') && default_column?(columns.fetch('lock_version'), :integer, '0') &&
      %w[account_id team_id created_at updated_at].none? { |name| columns.fetch(name).null }
  end

  def default_column?(column, type, default)
    column.type == type && !column.null && column.default.to_s == default
  end
end
