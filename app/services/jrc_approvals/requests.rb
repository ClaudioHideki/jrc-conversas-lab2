class JrcApprovals::Requests
  def initialize(account:, user:)
    @account, @user = account, user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def simulate(key:, resource_id:)
    snapshot, actor = capture(key, resource_id)
    versions = JrcApprovals::Selection.call(account: @account, key: key, snapshot: snapshot)
    { versions: versions.map { |version| { id: version.id, digest: version.digest, plan: plan!(version, snapshot, actor) } }, effects: [] }
  end

  def create!(key:, resource_id:, idempotency_key:)
    JrcApprovals::Ledger.key!(idempotency_key)
    JrcApprovals::Request.transaction do
      # Lock order shared with publishing, then scoped key: no phantom policy selection or partial accumulation.
      JrcApprovals::Ledger.lock!(@account.id, 'publication')
      snapshot, actor = capture(key, resource_id)
      JrcApprovals::Ledger.lock!(@account.id, "request:#{actor.id}:#{idempotency_key}")
      input_digest = JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => actor.id)
      existing = JrcApprovals::Request.where(account_id: @account.id, requester_id: actor.id, request_key: idempotency_key).to_a
      if existing.any?
        raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless existing.all? { |record| record.input_digest == input_digest }

        next existing
      end
      module_key, event_key = key.split('.', 2)
      JrcApprovals::Selection.call(account: @account, key: key, snapshot: snapshot).map do |version|
        plan = plan!(version, snapshot, actor)
        record = JrcApprovals::Request.create!(account: @account, policy_version: version, requester: actor,
          issuer_company_id: snapshot['issuer_company_id'], business_unit_id: snapshot['business_unit_id'],
          resource_type: snapshot['resource_type'], resource_id: snapshot['resource_id'], module_key: module_key, event_key: event_key,
          request_key: idempotency_key, input_digest: input_digest, snapshot: snapshot, stage_plan: plan,
          fingerprint: JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => actor.id,
            'policy_digest' => version.digest, 'policy_version_id' => version.id, 'stage_plan' => plan),
          expires_at: Time.current + version.definition.fetch('expires_in_seconds').seconds)
        JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'request_created', key: "request:#{record.id}:created",
          data: { fingerprint: record.fingerprint, state: record.state }, request_id: record.id, policy_version_id: version.id)
        record
      end
    end
  end

  # Trusted domain editing entry point: authorization precedes sensitive capture.
  # Only mismatched contexts can be invalidated; this grants no decision or management capability.
  def invalidate_resource!(key:, resource_id:, reason:)
    raise JrcApprovals::Error, 'REASON_REQUIRED' unless reason.is_a?(String) && reason.strip.present?

    @authorization.member!
    entry = JrcApprovals::Catalog.fetch(key)
    module_key, event_key = key.split('.', 2)
    records = JrcApprovals::Request.where(account_id: @account.id, resource_type: entry.model.name, resource_id: resource_id,
      module_key: module_key, event_key: event_key, state: %w[pending approved returned escalated])
    return unless records.exists?

    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: key, resource_id: resource_id)
    JrcApprovals::Request.transaction do
      records.order(:id).lock.each do |record|
        next if record.snapshot == snapshot

        record.update!(state: 'stale')
        JrcApprovals::Ledger.audit!(account: @account, actor: @authorization.member!, event: 'request_invalidate',
          key: "request:#{record.id}:#{record.lock_version}", data: { state: 'stale', reason: reason.strip }, request_id: record.id)
      end
    end
  end

  # Explicit E3 contract: callers must invoke this after relevant changes; there are no operational callbacks in E2.
  def transition!(request_id:, action:, expected_version:, reason:)
    raise JrcApprovals::Error, 'REASON_REQUIRED' unless reason.is_a?(String) && reason.strip.present?

    JrcApprovals::Request.transaction do
      record = JrcApprovals::Request.where(account_id: @account.id).lock.find(request_id)
      actor = @authorization.authorize!('request_create', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
      raise Pundit::NotAuthorizedError unless actor.id == record.requester_id ||
        @authorization.authorize!('policy_manage', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
      JrcApprovals::Ledger.expected!(record, expected_version)
      state = case action
              when 'cancel' then 'canceled' if %w[pending returned escalated].include?(record.state)
              when 'expire' then 'expired' if record.state == 'pending' && record.expires_at <= Time.current
              when 'invalidate'
                current = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: "#{record.module_key}.#{record.event_key}",
                                                        resource_id: record.resource_id)
                'stale' if %w[pending approved returned escalated].include?(record.state) && current != record.snapshot
              when 'reopen'
                'pending' if %w[returned escalated].include?(record.state) && record.expires_at > Time.current &&
                  record.policy_version.definition['reopen_mode'] == 'restart_all'
              end
      raise JrcApprovals::Error, 'INVALID_TRANSITION' unless state

      attributes = { state: state }
      attributes[:cycle] = record.cycle + 1 if action == 'reopen'
      record.update!(attributes)
      JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: "request_#{action}",
        key: "request:#{record.id}:#{record.lock_version}", data: { state: state, reason: reason.strip, cycle: record.cycle }, request_id: record.id)
      record
    end
  end

  private

  def capture(key, resource_id)
    @authorization.member!
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: key, resource_id: resource_id)
    actor = @authorization.authorize!('request_create', company_id: snapshot['issuer_company_id'], unit_id: snapshot['business_unit_id'])
    [snapshot, actor]
  end

  def plan!(version, snapshot, actor)
    conditions = JrcApprovals::Conditions.new(JrcApprovals::Catalog.fetch("#{version.policy.module_key}.#{version.policy.event_key}").fields)
    unless version.definition['steps'].all? { |step| conditions.match?(step['authority'], snapshot.fetch('values')) }
      raise JrcApprovals::Error, 'AUTHORITY_NOT_APPLICABLE'
    end
    JrcApprovals::Eligibility.new(account: @account, company_id: snapshot['issuer_company_id'], unit_id: snapshot['business_unit_id'],
      catalog_key: "#{version.policy.module_key}.#{version.policy.event_key}")
      .plan!(version.definition, requester_id: actor.id)
  end
end
