class JrcApprovals::Simulation
  def initialize(account:, user:)
    @account, @user = account, user
  end

  def call(key:, resource_id: nil, context: nil)
    raise JrcApprovals::Error, 'INVALID_INPUT' if resource_id.present? == context.present?

    entry = JrcApprovals::Catalog.fetch(key)
    snapshot = if resource_id.present?
                 JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: key, resource_id: resource_id)
               else
                 synthetic!(entry, context)
               end
    actor = JrcApprovals::Authorization.new(account: @account, user: @user)
      .authorize!('policy_manage', company_id: snapshot['issuer_company_id'], unit_id: snapshot['business_unit_id'])
    versions = JrcApprovals::Selection.call(account: @account, key: key, snapshot: snapshot)
    result = versions.map { |version| project_version(version, snapshot, actor) }
    { versions: result, predicted_state: 'pending', effects: [] }
  rescue JrcApprovals::Error => e
    conflicts = %w[POLICY_REQUIRED POLICY_SELECTION_CONFLICT INSUFFICIENT_APPROVERS AUTHORITY_NOT_APPLICABLE TIER_NOT_APPLICABLE]
    raise unless conflicts.include?(e.code)

    { versions: [], conflict: e.code, predicted_state: 'blocked', effects: [] }
  end

  private

  def project_version(version, snapshot, actor)
    plan = JrcApprovals::ApprovalPlan.new(account: @account).call(version: version, snapshot: snapshot, requester_id: actor.id)
    { id: version.id, digest: version.digest, authority_applicable: true, plan: plan }
  rescue JrcApprovals::Error => e
    legacy_failure = version.definition['schema_version'] == 1 && e.code == 'AUTHORITY_NOT_APPLICABLE'
    raise unless legacy_failure

    { id: version.id, digest: version.digest, authority_applicable: false, plan: [] }
  end

  def synthetic!(entry, context)
    data = JrcServiceDesk::CanonicalJson.normalize(context)
    raise JrcApprovals::Error, 'INVALID_CONTEXT' unless data.keys.sort == %w[business_unit_id issuer_company_id values]

    JrcApprovals::Authorization.new(account: @account, user: @user)
      .authorize!('policy_manage', company_id: data['issuer_company_id'], unit_id: data['business_unit_id'])
    raise JrcApprovals::Error, 'INVALID_CONTEXT' unless data['values'].is_a?(Hash) && data['values'].keys.sort == entry.fields.keys.sort

    entry.fields.each { |field, type| JrcApprovals::Conditions.value!(type, data['values'][field]) }
    data.merge('origin' => { 'catalog_key' => entry.key, 'catalog_version' => entry.version, 'synthetic' => true })
  end
end
