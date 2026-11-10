# Only explicitly installed type/field pairs can mutate an origin. Read adapters stay read-only.
class JrcApprovals::Adjustments
  KEYS = JrcApprovals::AdjustmentSources::SOURCES.keys.freeze
  FIELDS = JrcApprovals::AdjustmentPolicy::FIELDS.keys.freeze

  def initialize(account:, user:)
    @account = account
    @user = user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def options(record)
    resource = source!(record)
    authorize!(record, resource)
    return unless current_choices(record).any? && !source_locked?(resource)

    fields = record.policy_version.definition.dig('adjustments', 'fields')
    financial = %w[proposal_terms order_terms].include?(record.event_key)
    return if financial && fields.blank?
    { values: financial ? JrcApprovals::FinancialCatalog.values(resource).slice(*fields.keys) : resource.attributes.slice('discount_cents'),
      fields: fields, financial: financial, currency: record.snapshot.dig('values', 'currency'),
      maximum_discount_cents: resource.financial_summary.fetch(:products_cents) }
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcApprovals::Error, JrcCrm::CommercialFinancials::InvalidTerms
    nil
  end

  def call(request_id:, **input)
    intent = JrcApprovals::AdjustmentIntent.new(input)
    original = JrcApprovals::Request.where(account_id: @account.id).find(request_id)
    resource = source!(original)
    JrcApprovals::Request.transaction do
      # Source first, like native CRM edits; invalidation subsequently locks requests in id order.
      resource.lock!
      actor = authorize!(original, resource)
      correlation = "adjustment:#{actor.id}:#{intent.idempotency_key}"
      JrcApprovals::Ledger.lock!(@account.id, correlation)
      existing = JrcApprovals::AuditEvent.find_by(account_id: @account.id, correlation_key: correlation)
      next replay!(existing, intent.digest(original.id), resource) if existing

      perform!(original, resource, actor, intent)
    end
  end

  private

  def perform!(original, resource, actor, intent)
    ensure_current!(original, intent)
    key = "#{original.module_key}.#{original.event_key}"
    zone = Time.find_zone(@account.reporting_timezone) || Time.zone
    JrcApprovals::AdjustmentPolicy.authorize!(original.policy_version.definition, key, intent.changes, today: Time.current.in_time_zone(zone).to_date)
    before = source_values(resource).slice(*intent.changes.keys)
    raise JrcApprovals::Error, 'NO_ADJUSTMENT_CHANGE' if before == intent.changes

    mutate_source!(resource, intent.changes)
    unless intent.changes.all? { |field, value| field == 'discount_cents' ? resource.financial_summary.fetch(:discount_cents) == value : source_values(resource)[field] == value }
      raise JrcApprovals::Error, 'INVALID_COMMERCIAL_TERMS'
    end

    revised = revise!(original, resource, actor, intent.digest(original.id))
    if intent.mode == 'approve'
      available = current_choices(revised)
      matching = available.any? { |step| step[:step_code] == intent.step_code && step[:choices].any? { |choice| choice[:actions].include?('approved') && choice[:delegation_id] == intent.delegation_id && choice[:own_delegation_id] == intent.own_delegation_id } }
      if matching
        approve!(revised, intent, intent.digest(original.id))
      else
        # The native recalculated plan owns the next authority. No vote is invented.
        raise JrcApprovals::Error, 'APPROVER_CONFIGURATION_REQUIRED' if revised.stage_plan.empty?
        JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'adjustment_routed', key: "adjustment_route:#{revised.id}",
          data: { original_request_id: original.id, revised_request_id: revised.id, reason: intent.reason }, request_id: revised.id,
          policy_version_id: revised.policy_version_id)
      end
    end
    JrcApprovals::Authorization.new(account: @account, user: @user).authorize!('adjust', company_id: revised.issuer_company_id, unit_id: revised.business_unit_id)
    source_mutation(resource).authorize!(resource, @user)
    audit!(original, revised, actor, before, intent)
    revised
  end

  def ensure_current!(original, intent)
    original.lock!
    JrcApprovals::Ledger.expected!(original, intent.expected_version)
    raise JrcApprovals::Error, 'REQUEST_EXPIRED' if original.expires_at <= Time.current
    raise Pundit::NotAuthorizedError if current_choices(original).empty?
  end

  def audit!(original, revised, actor, before, intent)
    JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'request_adjusted',
                                key: "adjustment:#{actor.id}:#{intent.idempotency_key}",
                                data: { input_digest: intent.digest(original.id), original_request_id: original.id, revised_request_id: revised.id,
                                        before: before, after: intent.changes, reason: intent.reason, mode: intent.mode,
                                        currency: original.snapshot.dig('values', 'currency') },
                                request_id: original.id, policy_version_id: original.policy_version_id)
  end

  def source!(record)
    key = "#{record.module_key}.#{record.event_key}"
    type = JrcApprovals::AdjustmentSources.type!(key: key, resource_type: record.resource_type)
    model = type == 'JrcCrm::Proposal' ? JrcCrm::Proposal : JrcCrm::SalesOrder
    model.where(account_id: @account.id).find(record.resource_id)
  end

  def authorize!(record, resource)
    JrcApprovals::RequestVisibility.authorize!(account: @account, user: @user, record: record)
    actor = @authorization.authorize!('adjust', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    source_mutation(resource).authorize!(resource, @user)
    actor
  end

  def source_values(resource)
    resource.attributes.slice(*FIELDS).merge(JrcApprovals::FinancialCatalog.values(resource))
  end

  def source_mutation(resource)
    resource.is_a?(JrcCrm::SalesOrder) ? JrcCrm::OrderDiscountMutation : JrcCrm::ProposalMutation
  end

  def source_locked?(resource)
    resource.is_a?(JrcCrm::SalesOrder) ? JrcCrm::OrderDiscountMutation.locked?(resource) : resource.locked_for_editing?
  end

  def mutate_source!(resource, changes)
    if resource.is_a?(JrcCrm::SalesOrder)
      service = changes.keys == ['discount_cents'] ? JrcCrm::OrderDiscountMutation : JrcCrm::OrderTermsMutation
      service.call!(order: resource, actor: @user, attributes: changes)
    else
      JrcCrm::ProposalMutation.call!(proposal: resource, actor: @user, attributes: changes)
    end
  end

  def current_choices(record)
    JrcApprovals::DecisionOptions.call(account: @account, user: @user, record: record)
  end

  def revise!(original, resource, actor, digest)
    snapshot = JrcApprovals::Catalog.snapshot(account: @account, user: @user,
                                              key: "#{original.module_key}.#{original.event_key}", resource_id: resource.id)
    JrcApprovals::RequestRevision.create!(account: @account, user: actor.user, original: original,
                                          snapshot: snapshot, request_key: "adjust:#{digest}")
  end

  def approve!(record, intent, digest)
    JrcApprovals::Decisions.new(account: @account, user: @user).call(request_id: record.id, step_code: intent.step_code,
                                                                     decision: 'approved', reason: intent.reason,
                                                                     expected_version: record.lock_version,
                                                                     idempotency_key: "adjust:#{digest}", delegation_id: intent.delegation_id,
                                                                     own_delegation_id: intent.own_delegation_id)
    record.reload
  end

  def replay!(audit, digest, resource)
    raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless audit.data['input_digest'] == digest

    revised = JrcApprovals::Request.where(account_id: @account.id).find(audit.data.fetch('revised_request_id'))
    current = JrcApprovals::Catalog.snapshot(account: @account, user: @user,
                                             key: "#{revised.module_key}.#{revised.event_key}", resource_id: resource.id)
    raise JrcApprovals::Error, 'CONTEXT_STALE' unless current == revised.snapshot

    revised
  end
end
