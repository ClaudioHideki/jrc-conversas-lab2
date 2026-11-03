module JrcMigrations::Visibility
  # NICO-only filter. Operational human views keep their existing authorization.
  def self.scope(relation, account:, domain:)
    raise JrcMigrations::Error, 'UNSUPPORTED_DOMAIN' unless JrcMigrations::Catalog::FIELDS.key?(domain)

    adapter = JrcMigrations::Catalog.adapter(domain, account: account, source: nil)
    raise JrcMigrations::Error, 'INVALID_DESTINATION' unless relation.klass.table_name == adapter.model.table_name

    pending = JrcMigrations::Mapping.where(account_id: account.id, domain: domain, accepted_at: nil).select(:target_id)
    relation.where(id: adapter.scope.select(:id)).where.not(id: pending)
  end

  def self.allowed?(record, account:, domain:)
    scope(record.class.all, account: account, domain: domain).exists?(id: record.id)
  end
end
