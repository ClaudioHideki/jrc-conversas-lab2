class AddContactCenterAccessGrants < ActiveRecord::Migration[7.1]
  CAPABILITIES = %w[
    jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_supervise jrc_contact_center_configure
    jrc_contact_center_reports jrc_contact_center_administer jrc_contact_center_monitor jrc_contact_center_recordings_view
    jrc_contact_center_recordings_listen jrc_contact_center_recordings_download jrc_contact_center_publish
    jrc_contact_center_approve jrc_contact_center_audit
  ].freeze

  def up
    return verify_existing_table if table_exists?(:jrc_contact_center_access_grants)

    create_grants
    preserve_existing_members
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Explicit eligibility and authority history require a separately reviewed rollback'
  end

  private

  def verify_existing_table
    table = :jrc_contact_center_access_grants
    columns = connection.columns(table).map(&:name).sort
    expected = %w[id account_id account_user_id team_id eligible allowed denied created_at updated_at].sort
    checks = connection.check_constraints(table).map(&:name).sort
    expected_checks = %w[cc_access_one_subject cc_access_team_allow_only cc_access_allowed_known cc_access_denied_known].sort
    valid = columns == expected && checks == expected_checks && connection.foreign_keys(table).length == 3
    raise ActiveRecord::MigrationError, 'Unexpected access grant schema; review before reexecution' unless valid
  end

  def create_grants
    create_table :jrc_contact_center_access_grants do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :account_user, index: { unique: true }
      t.references :team, index: { unique: true }
      t.boolean :eligible, null: false, default: false
      t.text :allowed, array: true, null: false, default: []
      t.text :denied, array: true, null: false, default: []
      t.timestamps
    end
    add_subject_constraints
    add_capability_constraints
  end

  def add_subject_constraints
    add_check_constraint :jrc_contact_center_access_grants, '(account_user_id IS NULL) <> (team_id IS NULL)', name: 'cc_access_one_subject'
    add_check_constraint :jrc_contact_center_access_grants, "team_id IS NULL OR (NOT eligible AND denied = '{}'::text[])",
                         name: 'cc_access_team_allow_only'
    add_index :account_users, [:id, :account_id], unique: true, name: 'cc_access_member_account_key', if_not_exists: true
    add_index :teams, [:id, :account_id], unique: true, name: 'cc_access_team_account_key', if_not_exists: true
    add_foreign_key :jrc_contact_center_access_grants, :account_users,
                    column: [:account_user_id, :account_id], primary_key: [:id, :account_id], on_delete: :cascade
    add_foreign_key :jrc_contact_center_access_grants, :teams,
                    column: [:team_id, :account_id], primary_key: [:id, :account_id], on_delete: :cascade
  end

  def add_capability_constraints
    allowed = CAPABILITIES.map { |value| connection.quote(value) }.join(', ')
    %w[allowed denied].each do |field|
      add_check_constraint :jrc_contact_center_access_grants, "#{field} <@ ARRAY[#{allowed}]::text[]", name: "cc_access_#{field}_known"
    end
  end

  def preserve_existing_members
    execute <<~SQL
      INSERT INTO jrc_contact_center_access_grants (account_id, account_user_id, eligible, created_at, updated_at)
      SELECT account_users.account_id, account_users.id, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM account_users INNER JOIN accounts ON accounts.id = account_users.account_id
      ON CONFLICT (account_user_id) DO NOTHING
    SQL
  end
end
