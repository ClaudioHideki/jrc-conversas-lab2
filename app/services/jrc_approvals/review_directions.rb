# Request a correction or send the exact current case to a configured native
# policy. Neither suggestions nor escalation mutate the commercial origin.
class JrcApprovals::ReviewDirections
  def initialize(account:, user:)
    @account, @user = account, user
  end

  def options(record)
    config = record.policy_version.definition['review_directions']
    return nil unless config
    return nil if config['actions'] == ['suggest_redaction'] && "#{record.module_key}.#{record.event_key}" != JrcApprovals::DraftReviewCatalog::KEY
    JrcApprovals::ReviewDirectivePolicy.validate!(config)
    choices = JrcApprovals::DecisionOptions.call(account: @account, user: @user, record: record)
    return nil unless choices.any?
    { actions: config['actions'], choices: choices, escalation_configured: config['escalation_policy_id'].present? }
  end

  def call(request_id:, kind:, text:, expected_version:, idempotency_key:, step_code:, delegation_id: nil, own_delegation_id: nil)
    JrcApprovals::Ledger.key!(idempotency_key)
    result = JrcApprovals::Request.transaction do
      auth = JrcApprovals::Authorization.new(account: @account, user: @user)
      actor = auth.member!
      JrcApprovals::Ledger.lock!(@account.id, 'publication')
      JrcApprovals::Ledger.lock!(@account.id, "review_direction:#{actor.id}:#{idempotency_key}")
      record = JrcApprovals::Request.where(account_id: @account.id).lock.find(request_id)
      JrcApprovals::RequestVisibility.authorize!(account: @account, user: @user, record: record)
      config = record.policy_version.definition['review_directions']
      reason = JrcApprovals::ReviewDirectivePolicy.input!(config, kind, text)
      key = "review_direction:#{actor.id}:#{idempotency_key}"
      digest = JrcApprovals::Ledger.digest(request_id: record.id, kind: kind, text: reason, expected_version: expected_version,
        step_code: step_code, delegation_id: delegation_id, own_delegation_id: own_delegation_id)
      existing = JrcApprovals::AuditEvent.find_by(account_id: @account.id, correlation_key: key)
      if existing
        raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless existing.data['input_digest'] == digest
        next { recorded: true, kind: kind, routed_request_id: existing.data['routed_request_id'], source_changed: false }
      end
      JrcApprovals::Ledger.expected!(record, expected_version)
      raise JrcApprovals::Error, 'REQUEST_NOT_PENDING' unless record.state == 'pending'
      check_mutable_source!(record, kind)
      raise JrcApprovals::Error, 'REQUEST_EXPIRED' if record.expires_at <= Time.current
      vote = kind == 'escalate' ? 'escalated' : 'returned'
      choices = JrcApprovals::DecisionOptions.call(account: @account, user: @user, record: record)
      permitted = choices.any? do |row|
        row[:step_code] == step_code && row[:choices].any? { |choice| choice[:actions].include?(vote) &&
          choice[:delegation_id] == delegation_id && choice[:own_delegation_id] == own_delegation_id }
      end
      raise Pundit::NotAuthorizedError unless permitted
      routed = escalate!(record, actor, config.fetch('escalation_policy_id'), key) if kind == 'escalate'
      JrcApprovals::Decisions.new(account: @account, user: @user).call(request_id: record.id, step_code: step_code,
        decision: vote, reason: reason, expected_version: expected_version, idempotency_key: "dir:#{digest}",
        delegation_id: delegation_id, own_delegation_id: own_delegation_id)
      check_mutable_source!(record, kind)
      JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'review_direction_recorded', key: key,
        data: { input_digest: digest, kind: kind, reason: reason, routed_request_id: routed&.id, source_changed: false },
        request_id: record.id, policy_version_id: record.policy_version_id)
      { recorded: true, kind: kind, routed_request_id: routed&.id, source_changed: false }
    end
    # A route can leave the sender's scope. Return a minimal acknowledgment only.
    if result[:routed_request_id]
      begin
        routed = JrcApprovals::Request.where(account_id: @account.id).find(result[:routed_request_id])
        JrcApprovals::RequestVisibility.authorize!(account: @account, user: @user, record: routed)
      rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
        result[:routed_request_id] = nil
      end
    end
    result
  end

  private

  def check_mutable_source!(record, kind)
    entry = JrcApprovals::Catalog.fetch("#{record.module_key}.#{record.event_key}")
    raise JrcApprovals::Error, 'SOURCE_LOCKED_NEW_PROCESS_REQUIRED' unless entry.model
    source = entry.model.where(account_id: @account.id).find(record.resource_id)
    if kind == 'suggest_redaction' && entry.key != JrcApprovals::DraftReviewCatalog::KEY
      raise JrcApprovals::Error, 'REDACTION_REQUIRES_CONTRACT_DRAFT'
    end
    locked = case source.class.name
             when 'JrcCrm::Proposal' then source.locked_for_editing?
             when 'JrcCrm::SalesOrder' then JrcCrm::OrderDiscountMutation.locked?(source)
             when 'JrcCrm::Contract' then source.signature_status == 'signed' || source.status.in?(%w[active completed canceled terminated])
             when 'JrcCrm::BackofficeRequest' then source.status.in?(%w[completed canceled rejected])
             else true
             end
    raise JrcApprovals::Error, 'SOURCE_LOCKED_NEW_PROCESS_REQUIRED' if locked
    raise JrcApprovals::Error, 'REDACTION_REQUIRES_CONTRACT_DRAFT' if kind == 'suggest_redaction' && source.class.name != 'JrcCrm::Contract'
  end

  def escalate!(original, actor, policy_id, key)
    policy = JrcApprovals::Policy.where(account_id: @account.id).find(policy_id)
    prior = original
    visited = []
    32.times do
      raise JrcApprovals::Error, 'ESCALATION_CYCLE' if visited.include?(prior.id) || prior.policy_version.policy_id == policy.id
      visited << prior.id
      provenance = JrcApprovals::AuditEvent.find_by(account_id: @account.id, correlation_key: "request:#{prior.id}:created")
      ancestor = provenance&.data&.fetch('original_request_id', nil)
      break unless ancestor
      prior = JrcApprovals::Request.where(account_id: @account.id).find(ancestor)
    end
    raise JrcApprovals::Error, 'ESCALATION_CHAIN_LIMIT' if visited.size >= 32
    raise JrcApprovals::Error, 'ESCALATION_CONFIGURATION_REQUIRED' unless policy.state == 'published' && policy.current_version_id
    version = policy.versions.find(policy.current_version_id)
    original_key = "#{original.module_key}.#{original.event_key}"
    target_key = "#{policy.module_key}.#{policy.event_key}"
    allowed_key = target_key == original_key || (target_key == JrcApprovals::CommercialCatalog::PRICE_FAMILY &&
      original.module_key == 'crm' && JrcApprovals::CommercialCatalog::PRICE_EVENTS.include?(original.event_key))
    raise JrcApprovals::Error, 'ESCALATION_SCOPE_MISMATCH' unless allowed_key &&
      [policy.issuer_company_id, policy.business_unit_id] == [original.issuer_company_id, original.business_unit_id]
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: original_key, resource_id: original.resource_id)
    raise JrcApprovals::Error, 'CONTEXT_STALE' unless snapshot == original.snapshot
    entry = JrcApprovals::Catalog.fetch(target_key)
    raise JrcApprovals::Error, 'ESCALATION_POLICY_NOT_APPLICABLE' unless JrcApprovals::Conditions.new(entry.fields).match?(version.definition['condition'], snapshot['values'])
    # Revalidate the original requester. The actor is never impersonated.
    JrcApprovals::Authorization.new(account: @account, user: original.requester.user).authorize!('request_create',
      company_id: original.issuer_company_id, unit_id: original.business_unit_id)
    plan = JrcApprovals::ApprovalPlan.new(account: @account).call(version: version, snapshot: snapshot, requester_id: original.requester_id)
    attrs = original.attributes.slice('resource_type', 'resource_id', 'module_key', 'event_key', 'issuer_company_id', 'business_unit_id')
    routed = JrcApprovals::Request.create!(attrs.merge(account: @account, policy_version: version, requester: original.requester,
      request_key: key, snapshot: snapshot, stage_plan: plan, expires_at: [original.expires_at, Time.current + version.definition['expires_in_seconds'].seconds].min,
      input_digest: JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => original.requester_id),
      fingerprint: JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => original.requester_id,
        'policy_digest' => version.digest, 'policy_version_id' => version.id, 'stage_plan' => plan)))
    JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'request_created', key: "request:#{routed.id}:created",
      data: { original_request_id: original.id, state: routed.state, reason: 'Configured escalation' }, request_id: routed.id, policy_version_id: version.id)
    routed
  end
end
