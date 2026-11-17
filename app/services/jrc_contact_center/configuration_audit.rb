# frozen_string_literal: true

class JrcContactCenter::ConfigurationAudit
  COMMENT = 'jrc_contact_center_configuration_v1'
  ROLE_COMMENT = 'JRC Call Center native capabilities'
  COMMENTS = [COMMENT, ROLE_COMMENT].freeze

  def self.write!(record, action:, before:, after:)
    fields = JrcContactCenter::ConfigurationAuditSnapshot::FIELDS.fetch(record.class.name)
    changed = record.saved_changes.keys - %w[id account_id created_at updated_at]
    omitted = changed - fields
    return if action == 'update' && before == after && omitted.empty?

    Audited.audit_class.create!(
      auditable: record, associated: record.account, user: Current.user, action: action,
      comment: COMMENT, audited_changes: {
        'attributes' => [before&.fetch('attributes'), after&.fetch('attributes')],
        'cc_scope' => { 'before' => before&.fetch('scope'), 'after' => after&.fetch('scope') },
        'omitted_fields' => omitted, 'schema_version' => 1
      }
    )
  end
end
