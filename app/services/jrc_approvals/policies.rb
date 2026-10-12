class JrcApprovals::Policies
  def initialize(account:, user:)
    @account, @user = account, user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def create!(code:, name:, module_key:, event_key:, issuer_company_id: nil, business_unit_id: nil, definition:)
    actor = @authorization.authorize!('policy_manage', company_id: issuer_company_id, unit_id: business_unit_id)
    JrcApprovals::Policy.transaction do
      policy = JrcApprovals::Policy.create!(account: @account, author: actor, code: code, name: name, module_key: module_key,
        event_key: event_key, issuer_company_id: issuer_company_id, business_unit_id: business_unit_id, draft_definition: definition)
      audit!(policy, actor, 'policy_drafted')
      policy
    end
  end

  def edit!(policy_id:, expected_version:, name:, definition:)
    mutate(policy_id, expected_version) do |policy, actor|
      policy.update!(name: name, draft_definition: definition, state: 'draft')
      audit!(policy, actor, 'policy_edited')
    end
  end

  def validate!(policy_id:, expected_version:)
    mutate(policy_id, expected_version) do |policy, actor|
      validate_definition!(policy)
      policy.update!(state: 'validated')
      audit!(policy, actor, 'policy_validated')
    end
  end

  def publish!(policy_id:, expected_version:)
    mutate(policy_id, expected_version, publication: true) do |policy, actor|
      raise JrcApprovals::Error, 'POLICY_NOT_VALIDATED' unless policy.state == 'validated'

      definition = validate_definition!(policy)
      conflicts!(policy, definition)
      entry = JrcApprovals::Catalog.fetch("#{policy.module_key}.#{policy.event_key}")
      publication = policy.attributes.slice('account_id', 'issuer_company_id', 'business_unit_id', 'module_key', 'event_key', 'code', 'name')
        .merge('catalog_version' => entry.version, 'scope_domain' => 'crm_organization')
      number = (policy.versions.maximum(:version) || 0) + 1
      version = policy.versions.create!(account: @account, publisher: actor, version: number, definition: definition,
        publication: publication, digest: JrcApprovals::Ledger.digest('definition' => definition, 'publication' => publication, 'version' => number))
      policy.update!(current_version: version, enabled: true, state: 'published')
      audit!(policy, actor, 'policy_published', policy_version_id: version.id)
    end
  end

  def retire!(policy_id:, expected_version:)
    mutate(policy_id, expected_version, publication: true) do |policy, actor|
      policy.update!(enabled: false, state: 'retired')
      audit!(policy, actor, 'policy_retired')
    end
  end

  private

  def mutate(id, expected, publication: false)
    JrcApprovals::Policy.transaction do
      JrcApprovals::Ledger.lock!(@account.id, 'publication') if publication
      policy = JrcApprovals::Policy.where(account_id: @account.id).lock.find(id)
      actor = @authorization.authorize!('policy_manage', company_id: policy.issuer_company_id, unit_id: policy.business_unit_id)
      JrcApprovals::Ledger.expected!(policy, expected)
      yield(policy, actor)
      policy.reload
    end
  end

  def validate_definition!(policy)
    entry = JrcApprovals::Catalog.fetch("#{policy.module_key}.#{policy.event_key}")
    definition = JrcApprovals::Definition.validate!(policy.draft_definition, entry)
    JrcApprovals::Eligibility.new(account: @account, company_id: policy.issuer_company_id,
      unit_id: policy.business_unit_id, catalog_key: entry.key).plan!(definition)
    definition
  end

  def conflicts!(policy, definition)
    events = JrcApprovals::CommercialCatalog.selection_events(policy.module_key, policy.event_key)
    others = JrcApprovals::Policy.where(account_id: @account.id, module_key: policy.module_key, event_key: events, enabled: true)
      .where.not(id: policy.id).includes(:current_version)
    others.each do |other|
      next if policy.issuer_company_id && other.issuer_company_id && policy.issuer_company_id != other.issuer_company_id
      next if policy.business_unit_id && other.business_unit_id && policy.business_unit_id != other.business_unit_id

      selection = other.current_version.definition.fetch('selection')
      requested = definition.fetch('selection')
      if selection['mode'] != requested['mode'] || (selection['mode'] == 'exclusive' && selection['priority'] == requested['priority'])
        raise JrcApprovals::Error, 'POLICY_SELECTION_CONFLICT'
      end
    end
  end

  def audit!(policy, actor, event, **references)
    JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: event, key: "policy:#{policy.id}:#{policy.lock_version}:#{event}",
      data: { state: policy.state, enabled: policy.enabled, draft_digest: JrcApprovals::Ledger.digest(policy.draft_definition) },
      policy_id: policy.id, **references)
  end
end
