# The native completion/fingerprint check, shared by domain gates. Decisions,
# delegation, quorum and policy selection remain in the one Central engine.
class JrcApprovals::RequestVerification
  def self.approved?(record, version, snapshot)
    return false unless record && record.snapshot == snapshot && record.state == 'approved' && record.expires_at > Time.current

    fingerprint = JrcApprovals::Ledger.digest('snapshot' => snapshot, 'requester_id' => record.requester_id,
                                              'policy_digest' => version.digest, 'policy_version_id' => version.id, 'stage_plan' => record.stage_plan)
    record.fingerprint == fingerprint && complete_votes?(record)
  end

  def self.complete_votes?(record)
    record.stage_plan.all? do |plan|
      record.decisions.where(cycle: record.cycle, step_code: plan['code'], decision: 'approved').count >= plan['quorum']
    end && !record.decisions.where(cycle: record.cycle).where.not(decision: 'approved').exists?
  end
  private_class_method :complete_votes?
end
