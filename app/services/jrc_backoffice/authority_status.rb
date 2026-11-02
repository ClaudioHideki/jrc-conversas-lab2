# Business gate over native requests and votes, not a second decision engine.
# Uses the policies pinned when this proposal was created. A later policy
# publication cannot silently rewrite an open representation case.
class JrcBackoffice::AuthorityStatus
  def initialize(proposal:, actor:)
    @proposal = proposal
    @actor = actor
    @access = JrcBackoffice::AuthorityAccess.new(account: proposal.account, actor: actor)
  end

  def call(verify: false)
    JrcApprovals::Authorization.new(account: @proposal.account, user: @actor).member!
    @access.read_case!(@proposal)
    source = JrcBackoffice::AuthoritySource.new(proposal: @proposal, actor: @actor)
    context = source.current
    records = @access.approval_requests(@proposal).where(request_key: "authority:#{@proposal.id}").order(:id).to_a
    snapshot = JrcApprovals::Catalog.snapshot(account: @proposal.account, user: @actor,
                                              key: JrcBackoffice::AuthorityCatalog::KEY, resource_id: @proposal.id)
    current = context[:current] && latest_proposal?
    approved = current && approved_records?(records, snapshot)
    verify_approved!(source, approved, verify)
    { status: approved ? 'verified' : 'blocked', proposal_id: @proposal.id,
      current: current, facts: context[:facts],
      requests: records.map { |record| request_row(record, snapshot) } }
  end

  private

  def request_row(record, snapshot)
    JrcApprovals::RequestVisibility.authorize!(account: @proposal.account, user: @actor, record: record)
    { id: record.id, state: record.snapshot == snapshot ? record.state : 'stale', readable: true }
  rescue Pundit::NotAuthorizedError
    { id: record.id, state: record.snapshot == snapshot ? record.state : 'stale', readable: false }
  end

  def verify_approved!(source, approved, verify)
    source.verify! if approved && verify
  end

  def approved_records?(records, snapshot)
    records.any? && records.all? { |record| JrcApprovals::RequestVerification.approved?(record, record.policy_version, snapshot) }
  end

  def latest_proposal?
    JrcBackoffice::AuthorityProposal.where(account_id: @proposal.account_id, backoffice_request_id: @proposal.backoffice_request_id,
                                           contract_version_id: @proposal.contract_version_id).order(revision: :desc).first&.id == @proposal.id
  end
end
