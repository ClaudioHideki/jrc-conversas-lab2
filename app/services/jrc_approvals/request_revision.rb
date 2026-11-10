# A new immutable request, never an overwrite or a vote carried from the old snapshot.
class JrcApprovals::RequestRevision
  def self.create!(account:, user:, original:, snapshot:, request_key:)
    validate_origin!(account, original, snapshot)
    record = JrcApprovals::Request.create!(revision_attributes(account, original, snapshot).merge(request_key: request_key))
    actor = account.account_users.find_by!(user_id: user.id)
    JrcApprovals::Ledger.audit!(account: account, actor: actor, event: 'request_revised', key: "request:#{record.id}:revised",
                                data: { original_request_id: original.id, fingerprint: record.fingerprint },
                                request_id: record.id, policy_version_id: original.policy_version_id)
    record
  end

  def self.validate_origin!(account, original, snapshot)
    version = original.policy_version
    entry = JrcApprovals::Catalog.fetch("#{original.module_key}.#{original.event_key}")
    unless JrcApprovals::Conditions.new(entry.fields).match?(version.definition.fetch('condition'), snapshot.fetch('values'))
      raise JrcApprovals::Error, 'ADJUSTMENT_OUTSIDE_POLICY'
    end

    JrcApprovals::Authorization.new(account: account, user: original.requester.user)
                               .authorize!('request_create', company_id: original.issuer_company_id, unit_id: original.business_unit_id)
  end

  def self.revision_attributes(account, original, snapshot)
    version = original.policy_version
    plan = JrcApprovals::ApprovalPlan.new(account: account).call(version: version, snapshot: snapshot, requester_id: original.requester_id)
    fingerprint = JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => original.requester_id,
                                              'policy_digest' => version.digest, 'policy_version_id' => version.id, 'stage_plan' => plan)
    original.attributes.slice('resource_type', 'resource_id', 'module_key', 'event_key', 'issuer_company_id', 'business_unit_id', 'expires_at')
            .merge(account: account, policy_version: version, requester: original.requester, snapshot: snapshot, stage_plan: plan,
                   fingerprint: fingerprint,
                   input_digest: JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => original.requester_id))
  end
  private_class_method :revision_attributes, :validate_origin!
end
