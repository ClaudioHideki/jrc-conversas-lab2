require 'json'
require 'digest'

# Projection of the native ledger. It never recalculates historical authority
# from today's eligibility, policy or delegation status, and never executes an origin.
class JrcApprovals::RequestReport
  MAX_ROWS = 1000
  AUDIT_FIELDS = %w[state decision reason principal_id step_code cycle fingerprint original_request_id revised_request_id mode currency].freeze
  ADJUSTMENT_FIELDS = %w[before after].freeze
  SUMMARY_FIELDS = %w[total_cents currency item_count price_status signature_evidence evidence_state signer_count joint_signature value_basis].freeze

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def call(id)
    record = JrcApprovals::Request.where(account_id: @account.id).find(id)
    record.with_lock('FOR SHARE') do
      authorize!(record)
      result = { schema_version: 1, generated_at: Time.current, request: JrcApprovals::RequestSerializer.new(record).as_json,
                 captured_rule: captured_rule(record), captured_plan: record.stage_plan,
                 captured_values: captured_values(record), decisions: decisions(record),
                 events: events(record), revisions: revisions(record),
                 identities: 'Immutable account-user IDs identify actors at the vote; names, where displayed, are current directory names.' }
      authorize!(record)
      bytes = JSON.pretty_generate(result.as_json)
      JrcApprovals::Ledger.audit!(account: @account, actor: @member, event: 'request_report_accessed',
                                  key: "request-report:#{SecureRandom.uuid}", request_id: record.id, policy_version_id: record.policy_version_id,
                                  data: { format: 'json', schema_version: 1, sha256: Digest::SHA256.hexdigest(bytes) })
      bytes
    end
  end

  private

  def authorize!(record)
    @account.reload
    @user.reload
    JrcApprovals::RequestVisibility.authorize!(account: @account, user: @user, record: record)
    @member = JrcApprovals::Authorization.new(account: @account, user: @user)
                                         .authorize!('view_audit', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
  end

  def limited(relation)
    rows = relation.limit(MAX_ROWS + 1).to_a
    raise JrcApprovals::Error, 'REPORT_TOO_LARGE' if rows.size > MAX_ROWS

    rows
  end

  def captured_rule(record)
    version = record.policy_version
    { id: version.id, version: version.version, digest: version.digest, published_at: version.created_at, publisher_id: version.publisher_id,
      publication: version.publication.slice('name', 'issuer_company_id', 'business_unit_id', 'module_key', 'event_key'),
      definition: version.definition.slice(*JrcApprovals::Definition::KEYS, 'tiers') }
  end

  def captured_values(record)
    fields = SUMMARY_FIELDS + rule_fields(record.policy_version.definition)
    record.snapshot.fetch('values').slice(*fields)
  end

  def rule_fields(value)
    case value
    when Hash
      Array(value['field']) + value.values.flat_map { |item| rule_fields(item) }
    when Array
      value.flat_map { |item| rule_fields(item) }
    else
      []
    end
  end

  def decisions(record)
    limited(record.decisions.where(account_id: @account.id).order(:id)).map do |vote|
      vote.attributes.slice('id', 'actor_id', 'principal_id', 'step_code', 'cycle', 'decision', 'reason', 'created_at', 'expected_version')
          .merge('delegation' => delegation(vote))
    end
  end

  def delegation(vote)
    return unless vote.delegation_id

    grant = JrcApprovals::Delegation.where(account_id: @account.id, policy_version_id: vote.request.policy_version_id).find(vote.delegation_id)
    own = own_grant(grant)
    grant.attributes.slice('id', 'principal_id', 'delegate_id', 'step_code', 'actions', 'starts_at', 'ends_at', 'revoked_at')
         .merge('own_delegation_id' => own&.fetch('id'), 'own_grant' => own)
  end

  def own_grant(delegation)
    id = JrcApprovals::OwnDelegationBindings.own_id(delegation)
    return unless id

    grant = JrcApprovals::OwnDelegations.find!(@account, id).record
    revoked = JrcApprovals::AuditEvent.find_by(account_id: @account.id, event_type: 'own_delegation_revoked',
                                               correlation_key: "own_delegation:revoked:#{id}")
    grant.attributes.slice('id', 'actor_id', 'created_at').merge(
      'terms' => grant.data.slice('delegate_id', 'issuer_company_id', 'business_unit_id', 'actions', 'starts_at', 'ends_at'),
      'revocation' => revoked&.attributes&.slice('id', 'actor_id', 'created_at')
    )
  end

  def events(record)
    rows = JrcApprovals::AuditEvent.where(account_id: @account.id, request_id: record.id).where.not(event_type: 'request_report_accessed')
    limited(rows.order(:id)).map do |event|
      data = event.data.slice(*AUDIT_FIELDS)
      ADJUSTMENT_FIELDS.each { |key| data[key] = event.data.fetch(key).slice('discount_cents') if event.data[key].is_a?(Hash) }
      event.attributes.slice('id', 'actor_id', 'event_type', 'decision_id', 'policy_version_id', 'created_at').merge('data' => data)
    end
  end

  def revisions(record)
    candidates = JrcApprovals::Request.where(account_id: @account.id, resource_type: record.resource_type, resource_id: record.resource_id,
                                             module_key: record.module_key, event_key: record.event_key)
    ids = connected_ids(record.id, revision_edges(candidates))
    limited(candidates.where(id: ids).order(:id)).filter_map do |revision|
      authorize!(revision)
      revision.attributes.slice('id', 'state', 'cycle', 'policy_version_id', 'fingerprint', 'created_at', 'updated_at')
    rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
      nil
    end
  end

  def revision_edges(candidates)
    links = JrcApprovals::AuditEvent.where(account_id: @account.id, request_id: candidates.select(:id),
                                           event_type: %w[request_revised request_adjusted])
    limited(links.order(:id)).map { |event| [event.data['original_request_id'], event.data['revised_request_id'] || event.request_id] }
  end

  def connected_ids(id, edges)
    ids = [id]
    loop do
      next_ids = (ids + edges.select { |edge| edge.intersect?(ids) }.flatten).compact.uniq
      return ids if ids == next_ids
      raise JrcApprovals::Error, 'REPORT_TOO_LARGE' if next_ids.size > MAX_ROWS

      ids = next_ids
    end
  end
end
