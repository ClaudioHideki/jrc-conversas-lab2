# Only this catalog enters its account-global native audit, never unrelated settings.
class JrcContactCenter::PauseCatalogAudit
  def self.write!(account:, before:, after:)
    return if before == after

    Audited.audit_class.create!(
      auditable: account, associated: account, user: Current.user, action: 'update',
      comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT, audited_changes: {
        'attributes' => [before.deep_dup, after.deep_dup],
        'cc_scope' => { 'before' => { 'account_id' => account.id.to_s }, 'after' => { 'account_id' => account.id.to_s } },
        'omitted_fields' => [], 'schema_version' => 1
      }
    )
  end
end
