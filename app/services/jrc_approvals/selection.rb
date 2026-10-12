class JrcApprovals::Selection
  def self.call(account:, key:, snapshot:)
    entry = JrcApprovals::Catalog.fetch(key)
    module_key, event_key = key.split('.', 2)
    events = JrcApprovals::CommercialCatalog.selection_events(module_key, event_key)
    versions = JrcApprovals::Policy.where(account_id: account.id, module_key: module_key, event_key: events, enabled: true)
      .includes(:current_version).filter_map do |policy|
      next if policy.issuer_company_id && policy.issuer_company_id != snapshot['issuer_company_id']
      next if policy.business_unit_id && policy.business_unit_id != snapshot['business_unit_id']

      version = policy.current_version
      policy_entry = JrcApprovals::Catalog.fetch("#{policy.module_key}.#{policy.event_key}")
      raise JrcApprovals::Error, 'INVALID_PUBLISHED_POLICY' unless version &&
        version.publication['catalog_version'] == policy_entry.version && policy_entry.fields == entry.fields
      definition = JrcApprovals::Definition.validate!(version.definition, entry)
      version if JrcApprovals::Conditions.new(entry.fields).match?(definition['condition'], snapshot.fetch('values'))
    end
    raise JrcApprovals::Error, 'POLICY_REQUIRED' if versions.empty?
    modes = versions.map { |version| version.definition.fetch('selection').fetch('mode') }.uniq
    raise JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT' unless modes.size == 1
    return versions if modes.first == 'accumulate'

    priority = versions.map { |version| version.definition.fetch('selection').fetch('priority') }.max
    selected = versions.select { |version| version.definition['selection']['priority'] == priority }
    raise JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT' unless selected.size == 1

    selected
  end
end
