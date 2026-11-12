# Commits intent only. Dispatch is a separate post-commit operation; this
# service deliberately makes no provider request or optimistic "sent" update.
class JrcBackoffice::Signatures::Admissions
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def create!(version_id:, authority_proposal_id:, expected_connection_id:, expected_source_digest:, idempotency_key:)
    JrcApprovals::Ledger.key!(idempotency_key)
    input = { account_id: @account.id, request_id: @request_id.to_s, version_id: version_id.to_s, authority_proposal_id: authority_proposal_id.to_s,
              expected_connection_id: expected_connection_id.to_s, source_digest: expected_source_digest, actor_id: @actor.id }
    input_digest = JrcBackoffice::Signatures::DeliverySnapshot.digest(input)
    locked_context do |request, contract|
      replayed!(idempotency_key, input_digest) || admit!(request, contract, input, input_digest, idempotency_key)
    end
  end

  def scope
    request = @access.request(@request_id)
    JrcBackoffice::SignatureDelivery.where(account_id: @account.id, backoffice_request_id: request.id,
                                           contract_id: @access.contracts.select(:id))
  end

  def cancel_prepared!(id)
    locked_context do |_request, _contract|
      record = scope.lock('FOR NO KEY UPDATE').find(id)
      JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(record.authority_proposal)
      next record if record.state == 'canceled' && record.events.exists?(kind: 'canceled_before_send')
      raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_ALREADY_DISPATCHED' unless record.state == 'prepared'

      record.events.create!(account: @account, connection: record.connection, kind: 'canceled_before_send', event_key: 'cancel-prepared',
                            source_snapshot: JrcServiceDesk::CanonicalJson.dump('actor_id' => @actor.id))
      audit!(record, 'signature_delivery_canceled')
      record
    end
  end

  private

  def replayed!(key, digest)
    record = JrcBackoffice::SignatureDelivery.find_by(account_id: @account.id, created_by_id: @actor.id, idempotency_key: key)
    return unless record

    raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_INTENT_CHANGED' unless record.input_digest == digest

    scope.find(record.id)
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(record.authority_proposal)
    record
  end

  def admit!(request, contract, input, input_digest, key)
    JrcBackoffice::Signatures::DeliveryGuard.check_editable!(contract)
    version, proposal = legal_source!(contract, input)
    JrcBackoffice::ContractRelease.check!(order: request.sales_order, actor: @actor)
    JrcBackoffice::Requirements.check_before_signature!(request: request, actor: @actor)
    connection = JrcBackoffice::Signatures::ConnectionSelection.for_new_delivery(account: @account)
    raise JrcBackoffice::Signatures::DeliveryError, 'CONNECTION_CHANGED' unless connection.id.to_s == input[:expected_connection_id]

    source = JrcBackoffice::Signatures::DeliverySnapshot.capture(version: version, proposal: proposal, connection: connection, actor: @actor)
    @access.writable!(request)
    persist!(proposal: proposal, connection: connection, source: source, input_digest: input_digest, key: key)
  end

  def locked_context
    JrcBackoffice::SignatureDelivery.transaction do
      JrcApprovals::Ledger.lock!(@account.id, 'publication')
      @account.with_lock('FOR NO KEY UPDATE') do
        request = @access.writable!(@access.request(@request_id))
        request.sales_order.with_lock('FOR NO KEY UPDATE') do
          request.with_lock('FOR NO KEY UPDATE') do
            contract = @access.contract!(request)
            contract.with_lock('FOR NO KEY UPDATE') { yield(request, contract) }
          end
        end
      end
    end
  end

  def legal_source!(contract, input)
    version = JrcBackoffice::ContractVersion.where(account_id: @account.id, contract_id: contract.id,
                                                   backoffice_request_id: @request_id).find(input[:version_id])
    proposal = JrcBackoffice::AuthorityProposal.where(account_id: @account.id, contract_version_id: version.id).find(input[:authority_proposal_id])
    unless version.source_digest == input[:source_digest] && version.source_format_version == 2 && !contract.signature_status.in?(%w[sent signed])
      raise JrcBackoffice::Signatures::DeliveryError, 'CONTRACT_SOURCE_CHANGED'
    end
    if JrcBackoffice::SignatureDelivery.exists?(contract_version_id: version.id)
      raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_VERSION_ALREADY_REGISTERED'
    end

    [version, proposal]
  end

  def persist!(proposal:, connection:, source:, input_digest:, key:)
    version = proposal.contract_version
    record = JrcBackoffice::SignatureDelivery.create!(
      account: @account, contract: version.contract, backoffice_request: version.backoffice_request, contract_version: version,
      signer_roster: version.signer_roster, authority_proposal: proposal, connection: connection, created_by: @actor,
      idempotency_key: key, transaction_id: SecureRandom.uuid, input_digest: input_digest,
      source_snapshot: JrcServiceDesk::CanonicalJson.dump(source), source_digest: JrcBackoffice::Signatures::DeliverySnapshot.digest(source)
    )
    record.events.create!(account: @account, connection: connection, kind: 'prepared', event_key: 'admission', source_snapshot: '{}')
    audit!(record, 'signature_delivery_admitted')
    record
  end

  def audit!(record, event)
    JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id, event_type: event,
                               resource_type: record.class.name, resource_id: record.id,
                               metadata: { contract_version_id: record.contract_version_id, authority_proposal_id: record.authority_proposal_id,
                                           connection_id: record.connection_id, external_delivery: false })
  end
end
