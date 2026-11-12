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
                             ).merge(origin)
  end

  private

  def origin
    if @record.resource_type == 'JrcRelationship::BatchReview' &&
       @record.module_key == 'relationship' && @record.event_key == 'portfolio_distribution'
      return { 'origin' => { kind: 'portfolio_distribution', review_id: @record.resource_id } }
    end

    legal_case = @record.resource_type == 'JrcBackoffice::AuthorityProposal' && @record.module_key == 'contracts' &&
                 @record.event_key == 'signer_authority'
    return {} unless legal_case

    proposal = JrcBackoffice::AuthorityProposal.where(account_id: @record.account_id).find(@record.resource_id)
    { 'origin' => { kind: 'contract_authority', backoffice_request_id: proposal.backoffice_request_id,
                    contract_version_id: proposal.contract_version_id } }
  end

  def stages
    @record.stage_plan.map do |step|
      approved = @record.decisions.count do |vote|
        vote.cycle == @record.cycle && vote.step_code == step['code'] && vote.decision == 'approved'
      end
      { 'code' => step['code'], 'quorum' => step['quorum'], 'approved_count' => approved }
    end
  end
end
