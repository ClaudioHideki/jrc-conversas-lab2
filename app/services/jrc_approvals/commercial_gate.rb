class JrcApprovals::CommercialGate
  SETTINGS_KEY = 'jrc_approval_gates'.freeze

  def self.mode(account, key)
    return 'disabled' unless account.feature_enabled?('jrc_approvals')

    settings = account.custom_attributes.fetch(SETTINGS_KEY, {})
    raise JrcApprovals::Error, 'INVALID_GATE_MODE' unless settings.is_a?(Hash)

    value = settings.fetch(key, 'shadow')
    raise JrcApprovals::Error, 'INVALID_GATE_MODE' unless %w[shadow enforcement].include?(value)

    value
  end

  def self.check!(resource:, user:, key:)
    gate = new(account: resource.account, user: user)
    mode = mode(resource.account, key)
    return { mode: mode, status: 'legacy', required: false } if mode == 'disabled'

    result = gate.evaluate(key: key, resource_id: resource.id, lock: true)
    Rails.logger.info("approval_gate mode=#{mode} key=#{key} resource=#{resource.id} status=#{result[:status]}")
    raise JrcApprovals::Error, result[:status] if mode == 'enforcement' && result[:status] != 'ready'

    result.merge(mode: mode)
  rescue JrcApprovals::Error, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, ArgumentError => error
    raise unless mode == 'shadow'

    Rails.logger.info("approval_gate mode=shadow key=#{key} resource=#{resource.id} status=#{error.class.name}")
    { mode: mode, status: 'observation_pending', required: false }
  end

  def self.check_contracts!(order:, user:)
    return unless mode(order.account, 'contracts.company_signature') == 'enforcement'

    order.contracts.where(signature_status: 'signed').order(:id).each do |contract|
      check!(resource: contract, user: user, key: 'contracts.company_signature')
    end
  end

  def initialize(account:, user:)
    @account, @user = account, user
  end

  def evaluate(key:, resource_id:, lock: false)
    JrcApprovals::Authorization.new(account: @account, user: @user).member!
    # In effect transactions, keep native reference rows stable until commit.
    if lock
      JrcApprovals::Ledger.lock!(@account.id, 'publication')
      entry = JrcApprovals::Catalog.fetch(key)
      resource = entry.model.where(account_id: @account.id).find(resource_id)
      raise Pundit::NotAuthorizedError unless entry.authorize.call(@user, resource)

      commercial = JrcApprovals::CommercialCatalog.commercial_resource(resource)
      items = case commercial
              when JrcCrm::Proposal then commercial.proposal_items
              when JrcCrm::Deal then commercial.deal_products
              else commercial.order_items
              end
      ids = items.pluck(:product_id)
      JrcCrm::Product.where(account_id: @account.id, id: ids).order(:id).lock('FOR SHARE').load
    end
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: key, resource_id: resource_id)
    values = snapshot.fetch('values')
    signature = key == 'contracts.company_signature'
    return payload('PRICE_CONTEXT_PENDING', snapshot) if !signature && values['price_status'] != 'evaluated'
    return payload('ready', snapshot, required: false) if !signature && values['below_minimum_count'].zero? && key != 'backoffice.release'

    versions = JrcApprovals::Selection.call(account: @account, key: key, snapshot: snapshot)
    records = matching_records(key, resource_id, lock)
    approved = versions.all? do |version|
      # A newer pending/negative request cannot fall back to an older approval.
      record = records.reverse.find { |candidate| candidate.policy_version_id == version.id }
      record && record.snapshot == snapshot && record.state == 'approved' && record.expires_at > Time.current &&
        record.fingerprint == JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => record.requester_id,
          'policy_digest' => version.digest, 'policy_version_id' => version.id, 'stage_plan' => record.stage_plan) &&
        record.stage_plan.all? do |plan|
          record.decisions.where(cycle: record.cycle, step_code: plan['code'], decision: 'approved').count >= plan['quorum']
        end && !record.decisions.where(cycle: record.cycle).where.not(decision: 'approved').exists?
    end
    status = approved ? 'ready' : 'APPROVAL_REQUIRED'
    status = 'COMPANY_SIGNATURE_EVIDENCE_REQUIRED' if signature && values['signature_evidence'] != 'verified'
    payload(status, snapshot).merge(policy_version_ids: versions.map(&:id), requests: records.map do |record|
      { id: record.id, state: record.snapshot == snapshot ? record.state : 'stale', policy_version_id: record.policy_version_id }
    end)
  rescue JrcApprovals::Error => error
    raise if %w[INVALID_GATE_MODE ADAPTER_NOT_INSTALLED].include?(error.code)

    { status: error.code, required: true, policy_version_ids: [], requests: [] }
  end

  def request!(key:, resource_id:, idempotency_key:)
    JrcApprovals::Ledger.key!(idempotency_key)
    actor = JrcApprovals::Authorization.new(account: @account, user: @user).member!
    entry = JrcApprovals::Catalog.fetch(key)
    resource = entry.model.where(account_id: @account.id).find(resource_id)
    raise Pundit::NotAuthorizedError unless entry.authorize.call(@user, resource)

    unit = JrcApprovals::CommercialCatalog.business_unit(resource)
    JrcApprovals::Authorization.new(account: @account, user: @user)
      .authorize!('request_create', company_id: unit.company_id, unit_id: unit.id)
    if JrcApprovals::Request.where(account_id: @account.id, requester_id: actor.id, request_key: idempotency_key).exists?
      return JrcApprovals::Requests.new(account: @account, user: @user)
        .create!(key: key, resource_id: resource_id, idempotency_key: idempotency_key)
    end
    result = evaluate(key: key, resource_id: resource_id)
    return [] if result[:status] == 'ready' && !result[:required]
    raise JrcApprovals::Error, result[:status] if result[:status] == 'PRICE_CONTEXT_PENDING'

    JrcApprovals::Requests.new(account: @account, user: @user)
      .create!(key: key, resource_id: resource_id, idempotency_key: idempotency_key)
  end

  private

  def matching_records(key, id, lock)
    module_key, event_key = key.split('.', 2)
    scope = JrcApprovals::Request.where(account_id: @account.id, module_key: module_key, event_key: event_key,
      resource_type: JrcApprovals::Catalog.fetch(key).model.name, resource_id: id).order(:id)
    scope = scope.lock if lock
    scope.to_a
  end

  def payload(status, snapshot, required: true)
    { status: status, required: required, context_digest: snapshot['values']['context_digest'],
      policy_version_ids: [], requests: [] }
  end
end
