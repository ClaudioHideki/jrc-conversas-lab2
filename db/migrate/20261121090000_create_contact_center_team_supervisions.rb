# frozen_string_literal: true

# Additive metadata only. No TeamMember, queue membership, coverage or capability is backfilled.
class CreateContactCenterTeamSupervisions < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_team_supervisions
  COLUMNS = %w[id account_id team_id account_user_id kind created_at updated_at].freeze
  MEMBER_INDEX = 'cc_team_supervision_member'.freeze
  PRIMARY_INDEX = 'cc_team_supervision_primary'.freeze
  KIND_CHECK = 'cc_team_supervision_kind'.freeze

  def up
    previous = connection.select_value('SHOW lock_timeout')
    connection.transaction(requires_new: true) do
      execute "SET LOCAL lock_timeout = '5s'"
      create_supervisions unless table_exists?(TABLE)
      verify_existing_table!
    end
  ensure
    execute "SET LOCAL lock_timeout = #{connection.quote(previous)}" if previous && connection.transaction_open?
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Preserve explicit team supervision and audit history; use a separately reviewed rollback'
  end

  private

  def create_supervisions
    create_table TABLE do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :team, null: false
      t.references :account_user, null: false
      t.text :kind, null: false
      t.timestamps
    end
    add_foreign_key TABLE, :teams, column: [:team_id, :account_id], primary_key: [:id, :account_id], on_delete: :cascade
    add_foreign_key TABLE, :account_users, column: [:account_user_id, :account_id], primary_key: [:id, :account_id], on_delete: :cascade
    add_index TABLE, [:team_id, :account_user_id], unique: true, name: MEMBER_INDEX
    add_index TABLE, :team_id, unique: true, where: "kind = 'primary'", name: PRIMARY_INDEX
    add_check_constraint TABLE, "kind IN ('primary', 'additional')", name: KIND_CHECK
  end

  def verify_existing_table!
    columns = connection.columns(TABLE).index_by(&:name)
    valid = columns.keys.sort == COLUMNS.sort && connection.primary_key(TABLE) == 'id'
    valid &&= valid_columns?(columns) && valid_keys? && valid_indexes? && valid_kind_check?
    raise ActiveRecord::MigrationError, 'Unexpected Call Center team supervision schema' unless valid
  end

  def valid_columns?(columns)
    return false unless columns.values.none?(&:null)

    ids = %w[id account_id team_id account_user_id]
    valid = ids.all? { |name| columns.fetch(name).type == :integer && columns.fetch(name).limit == 8 }
    valid &&= %w[created_at updated_at].all? { |name| columns.fetch(name).type == :datetime }
    valid && columns.fetch('kind').type == :text && valid_defaults?(columns)
  end

  def valid_defaults?(columns)
    (COLUMNS - ['id']).all? do |name|
      column = columns.fetch(name)
      column.default.nil? && column.default_function.nil?
    end
  end

  def valid_keys?
    keys = connection.foreign_keys(TABLE)
    keys.length == 3 && cascade_key?(keys, 'accounts', ['account_id'], ['id']) &&
      cascade_key?(keys, 'teams', %w[team_id account_id], %w[id account_id]) &&
      cascade_key?(keys, 'account_users', %w[account_user_id account_id], %w[id account_id])
  end

  def cascade_key?(keys, table, columns, primary)
    key = keys.find do |candidate|
      candidate.to_table == table && Array(candidate.column) == columns && Array(candidate.primary_key) == primary
    end
    valid_cascade_actions?(key)
  end

  def valid_cascade_actions?(key)
    key && key.on_delete == :cascade && key.options[:on_update].nil? &&
      key.options.fetch(:validate, true) && !key.options[:deferrable]
  end

  def valid_indexes?
    indexes = connection.indexes(TABLE)
    member = indexes.find { |index| index.name == MEMBER_INDEX }
    primary = indexes.find { |index| index.name == PRIMARY_INDEX }
    valid_reference_indexes?(indexes) && unique_index?(member, %w[team_id account_user_id], nil) &&
      unique_index?(primary, ['team_id'], "kind='primary'")
  end

  def valid_reference_indexes?(indexes)
    ordinary = indexes.reject { |index| [MEMBER_INDEX, PRIMARY_INDEX].include?(index.name) }
    valid = ordinary.length == 3 && ordinary.all? { |index| !index.unique && index.where.nil? }
    valid && ordinary.map(&:columns).sort == [%w[account_id], %w[account_user_id], %w[team_id]]
  end

  def unique_index?(index, columns, predicate)
    return false unless index && index.unique && index.columns == columns

    predicate ? normalize(index.where) == predicate : index.where.nil?
  end

  def valid_kind_check?
    checks = connection.check_constraints(TABLE)
    checks.one? && checks.first.name == KIND_CHECK && checks.first.validate? &&
      normalize(checks.first.expression) == "kind=ANYARRAY['primary','additional']"
  end

  def normalize(value)
    value.to_s.gsub('::text', '').delete('()').gsub(/\s+/, '')
  end
end
