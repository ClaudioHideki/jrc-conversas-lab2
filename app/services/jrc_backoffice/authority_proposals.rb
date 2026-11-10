# Atomically seals the evidence proposal and creates the native Central cases.
# No policy means rollback, never implicit approval. No provider is called here.
class JrcBackoffice::AuthorityProposals
  class Changed < StandardError; end

  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::AuthorityAccess.new(account: account, actor: actor)
  end

  def create!(**attributes)
    locked_context(attributes.fetch(:version_id)) do |version|
      input = normalize_input(attributes, version)
      digest = JrcBackoffice::AuthoritySource.digest(input)
      existing = scope.find_by(idempotency_key: attributes.fetch(:idempotency_key))
      if existing
        raise Changed unless existing.input_digest == digest

        next existing
      end
      create_case!(version, input, digest, attributes.fetch(:idempotency_key))
    end
  end

  def scope
    request = JrcBackoffice::ContractAccess.new(account: @account, actor: @actor).request(@request_id)
    JrcBackoffice::AuthorityProposal.where(account_id: @account.id, backoffice_request_id: request.id)
  end

  private

  def normalize_input(attributes, version)
    JrcApprovals::Ledger.key!(attributes.fetch(:idempotency_key))
    reason = attributes.fetch(:change_reason)
    raise ArgumentError, 'Justifique a proposta de representação.' unless reason.is_a?(String) && reason.strip.length.between?(1, 2000)
    raise Changed unless attributes.fetch(:expected_revision).to_s.match?(/\A\d{1,9}\z/)

    { version_id: version.id, revision: attributes.fetch(:expected_revision).to_i, source: attributes.fetch(:expected_source_digest),
      proofs: JrcBackoffice::AuthorityProofs.normalize(attributes.fetch(:proofs), version.signer_roster.snapshot),
      reason: reason.strip, actor_id: @actor.id }
  end

  def create_case!(version, input, digest, key)
    validate_current!(version, input)
    source = JrcBackoffice::AuthoritySource.build(version: version, proofs: input.fetch(:proofs))
    proposal = persist!(version, source, input, digest, key)
    JrcBackoffice::AuthoritySource.new(proposal: proposal, actor: @actor).verify!
    @access.authoring_version!(@request_id, version.id)
    JrcApprovals::Requests.new(account: @account, user: @actor).create!(
      key: JrcBackoffice::AuthorityCatalog::KEY, resource_id: proposal.id, idempotency_key: "authority:#{proposal.id}"
    )
    invalidate_previous!(proposal)
    audit!(proposal)
    proposal
  end

  def invalidate_previous!(proposal)
    native = JrcApprovals::Requests.new(account: @account, user: @actor)
    scope.where(contract_version_id: proposal.contract_version_id).where.not(id: proposal.id).find_each do |older|
      native.invalidate_resource!(key: JrcBackoffice::AuthorityCatalog::KEY, resource_id: older.id,
                                  reason: 'Nova comprovação de representação para a mesma versão contratual.')
    end
  end

  def validate_current!(version, input)
    raise Changed unless version.source_digest == input.fetch(:source) &&
                         scope.where(contract_version_id: version.id).maximum(:revision).to_i == input.fetch(:revision)
    raise Changed unless JrcBackoffice::AuthorityIntegrity.new(version: version, actor: @actor).call.values.all?
  end

  def locked_context(version_id)
    JrcBackoffice::AuthorityProposal.transaction do
      JrcApprovals::Ledger.lock!(@account.id, 'publication')
      @account.with_lock('FOR NO KEY UPDATE') do
        version = @access.authoring_version!(@request_id, version_id)
        version.contract.sales_order.with_lock('FOR NO KEY UPDATE') do
          version.backoffice_request.with_lock('FOR NO KEY UPDATE') do
            version.contract.with_lock('FOR NO KEY UPDATE') { yield(version) }
          end
        end
      end
    end
  end

  def persist!(version, source, input, digest, key)
    scope.create!(contract_version: version, signer_roster: version.signer_roster, contract: version.contract, created_by: @actor,
                  revision: input.fetch(:revision) + 1, idempotency_key: key, input_digest: digest, change_reason: input.fetch(:reason),
                  source_snapshot: JrcServiceDesk::CanonicalJson.dump(source), source_digest: JrcBackoffice::AuthoritySource.digest(source))
  end

  def audit!(proposal)
    JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id,
                               event_type: 'backoffice_authority_proposed', resource_type: 'JrcCrm::BackofficeRequest', resource_id: @request_id,
                               from_value: {}, to_value: { authority_proposal_id: proposal.id, contract_version_id: proposal.contract_version_id },
                               metadata: { source: 'backoffice_contract_authority', signing_authority_verified: false, external_delivery: false })
  end
end
