# One planner for native request creation and dry-run simulation.
class JrcApprovals::ApprovalPlan
  def initialize(account:)
    @account = account
  end

  def call(version:, snapshot:, requester_id:)
    key = "#{version.policy.module_key}.#{version.policy.event_key}"
    entry = JrcApprovals::Catalog.fetch(key)
    definition = JrcApprovals::Definition.validate!(version.definition, entry)
    steps = definition['steps']
    steps = JrcApprovals::TierRanges.new(definition, entry).steps!(snapshot.fetch('values')) if definition['schema_version'] == 2
    conditions = JrcApprovals::Conditions.new(entry.fields)
    raise JrcApprovals::Error, 'AUTHORITY_NOT_APPLICABLE' unless steps.all? { |step| conditions.match?(step['authority'], snapshot.fetch('values')) }

    eligibility = JrcApprovals::Eligibility.new(
      account: @account, company_id: snapshot['issuer_company_id'], unit_id: snapshot['business_unit_id'], catalog_key: key
    )
    eligibility.plan!(definition.merge('steps' => steps), requester_id: requester_id)
  end
end
