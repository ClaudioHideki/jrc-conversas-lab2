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
    JrcCrm::CorporateIssuer.authorize_resource!(resource, user)
    gate = new(account: resource.account, user: user)
    mode = mode(resource.account, key)
    ensure_gratuity_mode!(mode, resource)
    return { mode: mode, status: 'legacy', required: false } if mode == 'disabled'

    result = gate.evaluate(key: key, resource_id: resource.id, lock: true)
    Rails.logger.info("approval_gate mode=#{mode} key=#{key} resource=#{resource.id} status=#{result[:status]}")
    raise JrcApprovals::Error, result[:status] if mode == 'enforcement' && result[:status] != 'ready'

    result.merge(mode: mode)
  rescue JrcApprovals::Error, ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, ArgumentError => e
    raise unless shadow_failure?(mode, e)

    Rails.logger.info("approval_gate mode=shadow key=#{key} resource=#{resource.id} status=#{e.class.name}")
    { mode: mode, status: 'observation_pending', required: false }
  end

  def self.ensure_gratuity_mode!(mode, resource)
    raise JrcApprovals::Error, 'GRATUITY_POLICY_REQUIRED' if mode != 'enforcement' && JrcApprovals::GratuityCatalog.required?(resource)
  end

  def self.shadow_failure?(mode, error)
    mode == 'shadow' && (!error.respond_to?(:code) || error.code != 'GRATUITY_POLICY_REQUIRED')
  end

  def self.check_contracts!(order:, user:)
    return unless mode(order.account, 'contracts.company_signature') == 'enforcement'

    order.contracts.where(signature_status: 'signed').order(:id).each do |contract|
      check!(resource: contract, user: user, key: 'contracts.company_signature')
    end
  end

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def evaluate(key:, resource_id:, lock: false)
    result = evaluate_one(key: key, resource_id: resource_id, lock: lock)
    return result if JrcApprovals::GratuityCatalog.gratuity_key?(key)
    return result if JrcApprovals::Catalog.fetch(key).policy_only

    resource = JrcApprovals::Catalog.fetch(key).model.where(account_id: @account.id).find(resource_id)
    extra_key = JrcApprovals::GratuityCatalog.key_for(resource)
    return result unless extra_key

    commercial = JrcApprovals::CommercialCatalog.commercial_resource(resource)
    extra = evaluate_one(key: extra_key, resource_id: commercial.id, lock: lock)
    return result unless extra[:required]

    combine_results(result, extra)
  end

  def evaluate_one(key:, resource_id:, lock: false)
    JrcApprovals::Authorization.new(account: @account, user: @user).member!
    lock_context!(key, resource_id) if lock
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user, key: key, resource_id: resource_id)
    early = context_result(key, snapshot)
    return early if early

    selected_result(key, resource_id, snapshot, lock)
  rescue JrcApprovals::Error => e
    raise if %w[INVALID_GATE_MODE ADAPTER_NOT_INSTALLED].include?(e.code)

    { status: e.code, required: true, policy_version_ids: [], requests: [] }
  end

  def selected_result(key, resource_id, snapshot, lock)
    versions = JrcApprovals::Selection.call(account: @account, key: key, snapshot: snapshot)
    records = matching_records(key, resource_id, lock)
    status = approval_status(key, versions, records, snapshot)
    payload(status, snapshot).merge(policy_version_ids: versions.map(&:id), requests: request_states(records, snapshot))
  end

  def approval_status(key, versions, records, snapshot)
    return 'COMPANY_SIGNATURE_EVIDENCE_REQUIRED' if key == 'contracts.company_signature' && snapshot['values']['signature_evidence'] != 'verified'

    approved = versions.all? do |version|
      # A newer pending/negative request cannot fall back to an older approval.
      record = records.reverse.find { |candidate| candidate.policy_version_id == version.id }
      approved_record?(record, version, snapshot)
    end
    approved ? 'ready' : 'APPROVAL_REQUIRED'
  end

  def request!(key:, resource_id:, idempotency_key:)
    JrcApprovals::Ledger.key!(idempotency_key)
    actor = JrcApprovals::Authorization.new(account: @account, user: @user).member!
    resource = JrcCrm::CorporateIssuer.approval_resource!(@account, @user, key, resource_id)
    if !JrcApprovals::GratuityCatalog.gratuity_key?(key) && JrcApprovals::GratuityCatalog.required?(resource)
      return request_with_gratuity!(resource, key, idempotency_key)
    end
    return create_request(key, resource_id, idempotency_key) if JrcApprovals::Request.exists?(account_id: @account.id, requester_id: actor.id,
                                                                                              request_key: idempotency_key)

    result = evaluate_one(key: key, resource_id: resource_id)
    return [] if result[:status] == 'ready' && !result[:required]
    raise JrcApprovals::Error, result[:status] if result[:status] == 'PRICE_CONTEXT_PENDING'

    create_request(key, resource_id, idempotency_key)
  end

  private

  def create_request(key, resource_id, idempotency_key)
    JrcApprovals::Requests.new(account: @account, user: @user)
                          .create!(key: key, resource_id: resource_id, idempotency_key: idempotency_key)
  end

  def combine_results(result, extra)
    result.merge(status: result[:status] == 'ready' ? extra[:status] : result[:status], required: true, gratuity_required: true,
                 policy_version_ids: (result[:policy_version_ids] + extra[:policy_version_ids]).uniq,
                 requests: (result[:requests] + extra[:requests]).uniq)
  end

  def lock_context!(key, resource_id)
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
    JrcCrm::Product.where(account_id: @account.id, id: items.select(:product_id)).order(:id).lock('FOR SHARE').load
  end

  def context_result(key, snapshot)
    values = snapshot.fetch('values')
    return gratuity_context_result(snapshot) if JrcApprovals::GratuityCatalog.gratuity_key?(key)
    return if key == 'contracts.company_signature'
    return payload('PRICE_CONTEXT_PENDING', snapshot) if values['price_status'] != 'evaluated'

    payload('ready', snapshot, required: false) if values['below_minimum_count'].zero? && key != 'backoffice.release'
  end

  def gratuity_context_result(snapshot)
    values = snapshot.fetch('values')
    return payload('ready', snapshot, required: false) unless values['has_commercial_gratuity']
    return payload('GRATUITY_VALUE_PENDING', snapshot) if values['gratuity_value_status'] != 'evaluated'

    payload('PRICE_CONTEXT_PENDING', snapshot) if values['price_status'] != 'evaluated'
  end

  def approved_record?(record, version, snapshot)
    return false unless record && record.snapshot == snapshot && record.state == 'approved' && record.expires_at > Time.current

    fingerprint = JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => record.requester_id,
                                              'policy_digest' => version.digest, 'policy_version_id' => version.id, 'stage_plan' => record.stage_plan)
    record.fingerprint == fingerprint && complete_votes?(record)
  end

  def complete_votes?(record)
    record.stage_plan.all? do |plan|
      record.decisions.where(cycle: record.cycle, step_code: plan['code'], decision: 'approved').count >= plan['quorum']
    end && !record.decisions.where(cycle: record.cycle).where.not(decision: 'approved').exists?
  end

  def request_states(records, snapshot)
    records.map do |record|
      { id: record.id, state: record.snapshot == snapshot ? record.state : 'stale', policy_version_id: record.policy_version_id }
    end
  end

  def request_with_gratuity!(resource, key, idempotency_key)
    native = evaluate_one(key: key, resource_id: resource.id)
    raise JrcApprovals::Error, native[:status] if native[:status] == 'PRICE_CONTEXT_PENDING'

    commercial = JrcApprovals::CommercialCatalog.commercial_resource(resource)
    extra_key = JrcApprovals::GratuityCatalog.key_for(resource)
    extra = evaluate_one(key: extra_key, resource_id: commercial.id)
    raise JrcApprovals::Error, extra[:status] if %w[PRICE_CONTEXT_PENDING GRATUITY_VALUE_PENDING].include?(extra[:status])

    JrcApprovals::Request.transaction do
      service = JrcApprovals::Requests.new(account: @account, user: @user)
      records = native[:required] ? service.create!(key: key, resource_id: resource.id, idempotency_key: idempotency_key) : []
      extra_intent = Digest::SHA256.hexdigest("#{idempotency_key}:#{extra_key}:#{commercial.id}")
      records + service.create!(key: extra_key, resource_id: commercial.id, idempotency_key: extra_intent)
    end
  end

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
