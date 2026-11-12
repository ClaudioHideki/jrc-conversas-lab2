# Record the proven signature explicitly. Native activation, commercial gates,
# Backoffice advancement and CS acceptance remain separate domain operations.
class JrcBackoffice::Signatures::EvidenceAcceptance
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def call(delivery_id:, expected_source_digest:)
    @account.with_lock('FOR NO KEY UPDATE') do
      lock_identity!
      request = @access.writable!(@access.request(@request_id))
      request.sales_order.with_lock('FOR NO KEY UPDATE') do
        request.with_lock('FOR NO KEY UPDATE') do
          contract = @access.contract!(request)
          contract.with_lock('FOR NO KEY UPDATE') { accept!(contract, delivery_id, expected_source_digest) }
        end
      end
    end
  end

  private

  def lock_identity!
    User.where(id: @actor.id).lock('FOR SHARE').take!
    member = @account.account_users.where(user_id: @actor.id).lock('FOR SHARE').take!
    CustomRole.where(account_id: @account.id, id: member.custom_role_id).lock('FOR SHARE').take! if member.custom_role_id
    @account.jrc_crm_user_business_units.where(user_id: @actor.id).order(:id).lock('FOR SHARE').load
  end

  def accept!(contract, delivery_id, digest)
    delivery = JrcBackoffice::Signatures::Admissions.new(account: @account, actor: @actor, request_id: @request_id).scope.find(delivery_id)
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(delivery.authority_proposal)
    bundle = JrcBackoffice::SignatureArtifactBundle.where(account: @account, delivery: delivery).lock('FOR SHARE').take!
    fail!('SIGNATURE_EVIDENCE_IDENTITY_MISMATCH') unless digest == bundle.source_digest
    fail!('CONTRACT_SOURCE_CHANGED') unless JrcBackoffice::Signatures::EvidenceState.current_source?(contract, bundle)
    ensure_ready!(bundle)
    return bundle if already_accepted?(contract, bundle)

    fail!('CONTRACT_SIGNATURE_STATE_CONFLICT') unless contract.status.in?(%w[draft awaiting_signature])
    validate_history!(contract, bundle)
    accept_ready!(contract, delivery, bundle)
  end

  def accept_ready!(contract, delivery, bundle)
    [bundle.signed_document, bundle.certificate_document].each { |version| JrcBackoffice::DocumentSafety.new(version).bytes! }
    @access.writable!(@access.request(@request_id))
    JrcBackoffice::AuthorityAccess.new(account: @account, actor: @actor).read_case!(delivery.authority_proposal)
    ensure_ready!(bundle)
    fail!('CONTRACT_SOURCE_CHANGED') unless JrcBackoffice::Signatures::EvidenceState.current_source?(contract, bundle)
    persist_reference!(contract, bundle)
    record_signature!(contract, bundle)
    bundle
  end

  def ensure_ready!(bundle)
    status = JrcBackoffice::Signatures::EvidenceState.new(bundle).call
    fail!(status.fetch(:code)) unless status.fetch(:state) == 'verified'
  end

  def already_accepted?(contract, bundle)
    return false unless contract.signature_status == 'signed'

    fail!('SIGNATURE_HISTORY_CONFLICT') unless JrcBackoffice::Signatures::EvidenceState.matching_signed_file?(contract, bundle)
    true
  end

  def validate_history!(contract, bundle)
    external = contract.signature_external_id
    fail!('SIGNATURE_HISTORY_CONFLICT') if external.present? && external != bundle.delivery.external_id
    return unless contract.signed_document.attached? && contract.signed_document.blob.id != bundle.signed_document.file.blob.id

    fail!('SIGNATURE_HISTORY_CONFLICT')
  end

  def record_signature!(contract, bundle)
    before = contract.slice('signature_status', 'signature_mode', 'status')
    contract.signed_document.attach(bundle.signed_document.file.blob)
    contract.update!(signature_attributes(bundle))
    audit_acceptance!(contract, bundle, before)
  end

  def signature_attributes(bundle)
    source = bundle.delivery.snapshot
    signer = source.fetch('recipients').find { |row| row.fetch('party') == 'customer' }
    fail!('SIGNATURE_RECIPIENT_MISMATCH') unless signer

    signed_at = bundle.snapshot.fetch('signers').map { |row| Time.iso8601(row.fetch('signed_at')) }.max
    { signature_status: 'signed', signature_mode: 'provider', signature_provider: source.fetch('provider'),
      signature_external_id: bundle.delivery.external_id, signed_at: signed_at, signed_by_name: signer.fetch('name'), status: 'awaiting_signature' }
  end

  def audit_acceptance!(contract, bundle, before)
    JrcCrm::AuditEvent.create!(account: @account, actor_type: 'User', actor_id: @actor.id,
                               resource_type: contract.class.name, resource_id: contract.id,
                               event_type: 'backoffice_signature_evidence_accepted', from_value: before,
                               to_value: { signature_status: 'signed', status: contract.status },
                               metadata: { bundle_id: bundle.id, delivery_id: bundle.delivery_id,
                                           contract_version_id: bundle.contract_version_id, source_digest: bundle.source_digest })
  end

  def persist_reference!(contract, bundle)
    data = { 'format_version' => 1, 'account_id' => @account.id, 'contract_id' => contract.id, 'bundle_id' => bundle.id,
             'signed_blob_id' => bundle.signed_document.file.blob.id, 'accepted_by_id' => @actor.id,
             'bundle_digest' => bundle.source_digest, 'signed_sha256' => bundle.signed_document.sha256 }
    JrcBackoffice::SignatureAcceptance.create!(account: @account, contract: contract, bundle: bundle,
                                               signed_blob: bundle.signed_document.file.blob, accepted_by: @actor,
                                               source_snapshot: JrcServiceDesk::CanonicalJson.dump(data),
                                               source_digest: JrcBackoffice::SignatureAcceptance.digest(data))
  end

  def fail!(code)
    raise JrcBackoffice::Signatures::DeliveryError, code
  end
end
