class JrcApprovals::Decisions
  def initialize(account:, user:)
    @account, @user = account, user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def call(request_id:, step_code:, decision:, reason:, expected_version:, idempotency_key:, delegation_id: nil)
    JrcApprovals::Ledger.key!(idempotency_key)
    raise JrcApprovals::Error, 'REASON_REQUIRED' unless reason.is_a?(String) && reason.strip.present? && reason.bytesize <= 4096
    raise JrcApprovals::Error, 'INVALID_DECISION' unless JrcApprovals::Definition::ACTIONS.include?(decision)

    JrcApprovals::Request.transaction do
      member = @authorization.member!
      JrcApprovals::Ledger.lock!(@account.id, "decision:#{member.id}:#{idempotency_key}")
      request = JrcApprovals::Request.where(account_id: @account.id).lock.find(request_id)
      actor = @authorization.authorize!('decide', company_id: request.issuer_company_id, unit_id: request.business_unit_id)
      payload = { request_id: request.id, step_code: step_code, decision: decision, reason: reason.strip,
                  expected_version: expected_version, delegation_id: delegation_id }
      digest = JrcApprovals::Ledger.digest(payload)
      existing = JrcApprovals::Decision.find_by(account_id: @account.id, actor_id: actor.id, idempotency_key: idempotency_key)
      if existing
        raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless existing.payload_digest == digest
        raise JrcApprovals::Error, 'VERSION_CONFLICT' unless existing.cycle == request.cycle

        principal!(request, step_code, actor, delegation_id, decision)
        current!(request, replay: true)
        next existing
      end
      JrcApprovals::Ledger.expected!(request, expected_version)
      current!(request)
      step = request.policy_version.definition.fetch('steps').find { |item| item['code'] == step_code }
      raise JrcApprovals::Error, 'INVALID_STEP_ACTION' unless step && step['actions'].include?(decision)
      unless request.policy_version.definition['execution'] == 'parallel' || pending_steps(request).first == step_code
        raise JrcApprovals::Error, 'STEP_NOT_CURRENT'
      end
      raise JrcApprovals::Error, 'STEP_COMPLETED' unless pending_steps(request).include?(step_code)
      principal, delegation = principal!(request, step_code, actor, delegation_id, decision)
      if request.decisions.where(cycle: request.cycle, step_code: step_code)
        .where('principal_id = ? OR actor_id = ?', principal.id, actor.id).exists?
        raise JrcApprovals::Error, 'ALREADY_VOTED'
      end
      vote = request.decisions.create!(account: @account, actor: actor, principal: principal, delegation: delegation,
        step_code: step_code, cycle: request.cycle, decision: decision, reason: reason.strip,
        expected_version: expected_version, idempotency_key: idempotency_key, payload_digest: digest)
      state = decision == 'approved' ? (pending_steps(request).empty? ? 'approved' : 'pending') :
        (decision == 'rejected' ? step.fetch('on_reject') : decision)
      state == request.state ? request.touch : request.update!(state: state)
      JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'decision_recorded', key: "decision:#{vote.id}",
        data: { state: state, decision: decision, reason: reason.strip, principal_id: principal.id,
                step_code: step_code, cycle: request.cycle, fingerprint: request.fingerprint }, request_id: request.id, decision_id: vote.id)
      vote
    end
  end

  private

  def current!(request, replay: false)
    raise JrcApprovals::Error, 'REQUEST_EXPIRED' if request.expires_at <= Time.current
    raise JrcApprovals::Error, 'REQUEST_NOT_PENDING' unless request.state == 'pending' ||
      (replay && %w[approved rejected returned escalated].include?(request.state))

    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user,
      key: "#{request.module_key}.#{request.event_key}", resource_id: request.resource_id)
    raise JrcApprovals::Error, 'CONTEXT_STALE' unless snapshot == request.snapshot
  end

  def principal!(request, step_code, actor, delegation_id, decision)
    definition = request.policy_version.definition
    step = definition.fetch('steps').find { |item| item['code'] == step_code }
    plan = request.stage_plan.find { |item| item['code'] == step_code }
    raise JrcApprovals::Error, 'INVALID_STEP_ACTION' unless step && plan && step['actions'].include?(decision)
    delegation = nil
    principal = actor
    if delegation_id
      delegation = JrcApprovals::Delegation.where(account_id: @account.id, policy_version_id: request.policy_version_id,
                                                 delegate_id: actor.id, step_code: step_code).find(delegation_id)
      unless definition['delegation_allowed'] && delegation.revoked_at.nil? && delegation.starts_at <= Time.current &&
             delegation.ends_at > Time.current && delegation.actions.include?(decision)
        raise JrcApprovals::Error, 'INVALID_DELEGATION'
      end
      principal = delegation.principal
    end
    eligible = JrcApprovals::Eligibility.new(account: @account, company_id: request.issuer_company_id, unit_id: request.business_unit_id,
      catalog_key: "#{request.module_key}.#{request.event_key}")
    raise Pundit::NotAuthorizedError unless plan['principal_ids'].include?(principal.id) && eligible.candidates(step).include?(principal.id)
    if !definition['allow_self_approval'] && [actor.id, principal.id].include?(request.requester_id)
      raise Pundit::NotAuthorizedError
    end
    [principal, delegation]
  end

  def pending_steps(request)
    request.stage_plan.reject do |plan|
      request.decisions.where(cycle: request.cycle, step_code: plan['code'], decision: 'approved').count >= plan['quorum']
    end.map { |plan| plan['code'] }
  end
end
