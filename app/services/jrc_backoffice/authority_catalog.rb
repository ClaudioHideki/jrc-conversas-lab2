# Representation is a legal event in the existing Central, independent of
# commercial price exceptions and of the signature provider.
class JrcBackoffice::AuthorityCatalog
  KEY = 'contracts.signer_authority'.freeze
  FIELDS = { 'context_digest' => 'string', 'evidence_state' => 'string', 'signer_count' => 'integer',
             'joint_signature' => 'boolean', 'total_cents' => 'integer', 'value_basis' => 'string',
             'customer_kind' => 'string' }.freeze

  def self.install!
    model = JrcBackoffice::AuthorityProposal
    entries = JrcApprovals::Catalog.instance_variable_get(:@entries)
    return if entries[KEY]&.model.equal?(model)

    JrcApprovals::Catalog.instance_variable_get(:@mutex).synchronize { entries.delete(KEY) }
    JrcApprovals::Catalog.register(key: KEY, version: 1, model: model, fields: FIELDS,
                                   authorize: lambda { |actor, proposal|
                                     JrcBackoffice::AuthorityAccess.new(account: proposal.account, actor: actor).read_case!(proposal)
                                     true
                                   }, capture: ->(proposal, actor) { capture(proposal, actor) },
                                   verify: lambda { |proposal, actor|
                                     JrcBackoffice::AuthoritySource.new(proposal: proposal, actor: actor).verify!
                                   })
  end

  def self.capture(proposal, actor)
    context = JrcBackoffice::AuthoritySource.new(proposal: proposal, actor: actor).current
    roster = proposal.signer_roster.snapshot
    financials = proposal.contract_version.snapshot.fetch('financials')
    amount = financials.fetch('contract_total_cents') { financials.fetch('total_cents') }
    raise JrcApprovals::Error, 'AUTHORITY_VALUE_REQUIRED' unless amount.is_a?(Integer) && amount >= 0

    joint = %w[customer issuer].any? { |key| roster.fetch("#{key}_mode") == 'joint' }
    { issuer_company_id: proposal.issuer_company_id, business_unit_id: proposal.business_unit_id,
      values: { context_digest: context.fetch(:context_digest), evidence_state: context[:current] ? 'current' : 'stale',
                signer_count: roster.fetch('signers').count, joint_signature: joint,
                total_cents: amount, value_basis: 'native_contract_total_cents', customer_kind: roster.fetch('customer').fetch('person_kind') } }
  end
end
