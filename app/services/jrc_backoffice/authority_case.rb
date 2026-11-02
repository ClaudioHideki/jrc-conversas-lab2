# Bounded, authorized operational DTO. Protected identifiers/anchors, file
# contents, raw encrypted snapshots and provider credentials stay private.
class JrcBackoffice::AuthorityCase
  def initialize(proposal:, actor:)
    @proposal = proposal
    @actor = actor
    @access = JrcBackoffice::AuthorityAccess.new(account: proposal.account, actor: actor)
  end

  def call
    @access.read_case!(@proposal)
    version = @proposal.contract_version
    legal = JrcBackoffice::ContractSnapshot.presentation(version.snapshot)
    context = legal.slice('customer', 'issuer_company', 'financials', 'order_number', 'proposal_number')
    context['contract'] = legal.fetch('contract').slice('contract_number', 'contract_type', 'starts_on', 'ends_on', 'term_months',
                                                        'monthly_cents', 'one_time_cents', 'payment_condition', 'due_day')
    context['items'] = legal.fetch('items').map { |row| row.slice('product_id', 'name_snapshot', 'quantity', 'unit_price_cents', 'discount_cents') }
    payload = { proposal: @proposal.serializable_hash, version: version.serializable_hash,
                signers: @proposal.signer_roster.serializable_hash, context: context, status: status }
    @access.read_case!(@proposal)
    payload
  end

  private

  def status
    return { status: 'unavailable', code: 'APPROVALS_DISABLED' } unless @proposal.account.feature_enabled?('jrc_approvals')

    JrcBackoffice::AuthorityStatus.new(proposal: @proposal, actor: @actor).call
  end
end
