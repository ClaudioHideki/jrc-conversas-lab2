class JrcApprovals::RequestSerializer
  def initialize(record)
    @record = record
  end

  def as_json(*)
    @record.attributes.slice('id', 'state', 'lock_version', 'cycle', 'policy_version_id', 'resource_type', 'resource_id',
                             'module_key', 'event_key', 'expires_at', 'fingerprint').merge(
                               'issuer_company_id' => @record.issuer_company_id, 'business_unit_id' => @record.business_unit_id,
                               'created_at' => @record.created_at, 'updated_at' => @record.updated_at,
                               'requester_id' => @record.requester_id, 'requester_name' => @record.requester.user.name,
                               'policy_name' => @record.policy_version.publication['name'], 'policy_version' => @record.policy_version.version,
                               'stages' => stages
                             )
  end

  private

  def stages
    @record.stage_plan.map do |step|
      approved = @record.decisions.count do |vote|
        vote.cycle == @record.cycle && vote.step_code == step['code'] && vote.decision == 'approved'
      end
      { 'code' => step['code'], 'quorum' => step['quorum'], 'approved_count' => approved }
    end
  end
end
