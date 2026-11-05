# Only explicitly installed type/field pairs can mutate an origin. Read adapters stay read-only.
class JrcApprovals::Adjustments
  KEYS = %w[crm.proposal_send crm.proposal_convert].freeze
  FIELDS = %w[discount_cents].freeze

  def initialize(account:, user:)
    @account = account
    @user = user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def options(record)
    resource = source!(record)
    authorize!(record, resource)
    return unless current_choices(record).any? && !resource.locked_for_editing?

    { values: resource.attributes.slice(*FIELDS), currency: record.snapshot.dig('values', 'currency'),
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
    before = resource.attributes.slice(*FIELDS)
    raise JrcApprovals::Error, 'NO_ADJUSTMENT_CHANGE' if before == intent.changes

    JrcCrm::ProposalMutation.call!(proposal: resource, actor: @user, attributes: intent.changes)
    unless resource.financial_summary.fetch(:discount_cents) == intent.changes.fetch('discount_cents')
      raise JrcApprovals::Error, 'INVALID_COMMERCIAL_TERMS'
    end

    revised = revise!(original, resource, actor, intent.digest(original.id))
    approve!(revised, intent, intent.digest(original.id)) if intent.mode == 'approve'
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
    raise JrcApprovals::Error, 'ADJUSTMENT_NOT_SUPPORTED' unless KEYS.include?(key) && record.resource_type == 'JrcCrm::Proposal'

    JrcCrm::Proposal.where(account_id: @account.id).find(record.resource_id)
  end

  def authorize!(record, resource)
    JrcApprovals::RequestVisibility.authorize!(account: @account, user: @user, record: record)
    actor = @authorization.authorize!('adjust', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    JrcCrm::ProposalMutation.authorize!(resource, @user)
    actor
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
