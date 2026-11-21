class AddContactCenterQualityReviewAuthority < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_access_grants
  LEGACY_CAPABILITIES = %w[
    jrc_contact_center_view jrc_contact_center_operate jrc_contact_center_supervise jrc_contact_center_configure
    jrc_contact_center_reports jrc_contact_center_administer jrc_contact_center_monitor jrc_contact_center_recordings_view
    jrc_contact_center_recordings_listen jrc_contact_center_recordings_download jrc_contact_center_publish
    jrc_contact_center_approve jrc_contact_center_audit
  ].freeze
  REVIEW_CAPABILITY = 'jrc_contact_center_quality_review'.freeze
  FIELDS = %w[allowed denied].freeze
  SUBJECT_CONSTRAINTS = {
    'cc_access_one_subject' => '(account_user_id IS NULL) <> (team_id IS NULL)',
    'cc_access_team_allow_only' => "team_id IS NULL OR NOT eligible AND denied = '{}'::text[]"
  }.freeze

  def up
    connection.transaction(requires_new: true) do
      execute "SET LOCAL lock_timeout = '5s'"
      execute "LOCK TABLE #{connection.quote_table_name(TABLE)} IN ACCESS EXCLUSIVE MODE"
      verify_constraints!
      FIELDS.each { |field| upgrade_constraint(field) }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Review grants and explicit denials must not be removed by rollback'
  end

  private

  def expression(field, capabilities)
    entries = capabilities.map { |capability| "#{connection.quote(capability)}::text" }.join(', ')
    "#{field} <@ ARRAY[#{entries}]"
  end

  def constraints
    connection.check_constraints(TABLE).index_by(&:name)
  end

  def verify_constraints!
    checks = constraints
    expected = %w[cc_access_one_subject cc_access_team_allow_only cc_access_allowed_known cc_access_denied_known]
    valid = checks.keys.sort == expected.sort && connection.foreign_keys(TABLE).length == 3
    valid &&= supported_subject_constraints?(checks) && supported_capability_constraints?(checks)
    raise ActiveRecord::MigrationError, 'Unexpected access constraints; explicit review required before upgrade' unless valid
  end

  def supported_subject_constraints?(checks)
    SUBJECT_CONSTRAINTS.all? { |name, value| checks.fetch(name).validate? && checks.fetch(name).expression == value }
  end

  def supported_capability_constraints?(checks)
    FIELDS.all? { |field| supported_capability_constraint?(checks.fetch("cc_access_#{field}_known"), field) }
  end

  def supported_capability_constraint?(current, field)
    permitted = [expression(field, LEGACY_CAPABILITIES), expression(field, LEGACY_CAPABILITIES + [REVIEW_CAPABILITY])]
    current.validate? && permitted.include?(current.expression)
  end

  def upgrade_constraint(field)
    name = "cc_access_#{field}_known"
    expanded = expression(field, LEGACY_CAPABILITIES + [REVIEW_CAPABILITY])
    return if constraints.fetch(name).expression == expanded

    remove_check_constraint TABLE, name: name
    add_check_constraint TABLE, expanded, name: name
  end
end
