# frozen_string_literal: true

class JrcContactCenter::AcwFormAudit
  def self.write!(form, version, context)
    attributes = version.slice('revision', 'status', 'integrity_sha256')
    Audited.audit_class.create!(
      auditable: version, associated: context.fetch(:account), user: context.fetch(:user), action: 'create',
      comment: JrcContactCenter::ConfigurationAudit::ACW_FORM_COMMENT, audited_changes: {
        'attributes' => [nil, attributes], 'cc_scope' => { 'before' => nil, 'after' => form.scope_snapshot },
        'omitted_fields' => %w[name description definition], 'schema_version' => 1
      }
    )
  end
end
