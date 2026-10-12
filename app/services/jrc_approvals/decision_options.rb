class JrcApprovals::DecisionOptions
  def self.call(account:, user:, record:)
    auth = JrcApprovals::Authorization.new(account: account, user: user)
    actor = auth.authorize!('decide', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    return [] unless record.state == 'pending' && record.expires_at > Time.current

    snapshot = JrcApprovals::Catalog.snapshot(account: account, user: user,
      key: "#{record.module_key}.#{record.event_key}", resource_id: record.resource_id)
    return [] unless record.snapshot == snapshot

    definition = record.policy_version.definition
    pending = record.stage_plan.reject do |plan|
      record.decisions.where(cycle: record.cycle, step_code: plan['code'], decision: 'approved').count >= plan['quorum']
    end
    pending = pending.first(1) if definition['execution'] == 'sequential'
    pending.filter_map do |plan|
      step = definition['steps'].find { |entry| entry['code'] == plan['code'] }
      eligible = JrcApprovals::Eligibility.new(account: account, company_id: record.issuer_company_id, unit_id: record.business_unit_id,
        catalog_key: "#{record.module_key}.#{record.event_key}")
        .candidates(step)
      principals = plan['principal_ids'] & eligible
      principals -= record.decisions.where(cycle: record.cycle, step_code: step['code']).pluck(:principal_id)
      principals -= [record.requester_id] unless definition['allow_self_approval']
      next if record.decisions.where(cycle: record.cycle, step_code: step['code'], actor_id: actor.id).exists?

      options = []
      options << { delegation_id: nil, actions: step['actions'] } if principals.include?(actor.id)
      if definition['delegation_allowed'] && (definition['allow_self_approval'] || record.requester_id != actor.id)
        JrcApprovals::Delegation.where(account_id: account.id, policy_version_id: record.policy_version_id,
          delegate_id: actor.id, principal_id: principals,
          step_code: step['code'], revoked_at: nil).where('starts_at <= ? AND ends_at > ?', Time.current, Time.current).each do |delegation|
          next if record.decisions.where(cycle: record.cycle, step_code: step['code'], principal_id: delegation.principal_id).exists?

          options << { delegation_id: delegation.id, actions: step['actions'] & delegation.actions }
        end
      end
      { step_code: step['code'], choices: options } if options.any?
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcApprovals::Error
    []
  end
end
