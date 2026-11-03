# Readiness is a preview, never a grant. Admissions repeats the checks under
# native locks before committing the immutable intent; the worker checks again.
class JrcBackoffice::Signatures::Preparation
  def initialize(account:, actor:, request_id:)
    @account = account
    @actor = actor
    @request_id = request_id
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
  end

  def call
    request = @access.request(@request_id)
    return blocked('REQUEST_NOT_EDITABLE') unless @access.writable?(request)
    return blocked('CONTRACT_VERSION_REQUIRED') unless request.contract_id

    contract = @access.contract!(request)
    JrcBackoffice::Signatures::DeliveryGuard.check_editable!(contract)
    return blocked('CONTRACT_SOURCE_CHANGED') if contract.signature_status.in?(%w[sent signed])

    prepare!(request, contract)
  rescue JrcBackoffice::Signatures::DeliveryError, JrcBackoffice::Signatures::ProviderError, JrcApprovals::Error => e
    blocked(e.code)
  end

  private

  def prepare!(request, contract)
    version = current_version!(request, contract)
    proposal = approved_proposal!(request, version)
    JrcBackoffice::ContractRelease.check!(order: request.sales_order, actor: @actor)
    connection = JrcBackoffice::Signatures::ConnectionSelection.for_new_delivery(account: @account)
    @access.writable!(@access.request(request.id))
    { can_send: true, blocked_code: nil, version: version.slice('id', 'number', 'pdf_sha256'), authority_proposal_id: proposal.id,
      expected_source_digest: version.source_digest, connection: connection.serializable_hash }
  end

  def current_version!(request, contract)
    version = JrcBackoffice::ContractVersions.new(account: @account, actor: @actor, request_id: request.id)
                                             .scope.where(contract_id: contract.id).order(number: :desc).first
    raise JrcBackoffice::Signatures::DeliveryError, 'CONTRACT_VERSION_REQUIRED' unless version&.source_format_version == 2 && version.signer_roster_id
    if JrcBackoffice::SignatureDelivery.exists?(contract_version_id: version.id)
      raise JrcBackoffice::Signatures::DeliveryError, 'DELIVERY_VERSION_ALREADY_REGISTERED'
    end

    version
  end

  def approved_proposal!(request, version)
    proposal = JrcBackoffice::AuthorityProposal.where(account_id: @account.id, backoffice_request_id: request.id,
                                                      contract_version_id: version.id).order(revision: :desc).first
    raise JrcBackoffice::Signatures::DeliveryError, 'AUTHORITY_APPROVAL_REQUIRED' unless proposal

    status = JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: @actor).call(verify: true)
    raise JrcBackoffice::Signatures::DeliveryError, 'AUTHORITY_APPROVAL_REQUIRED' unless status[:status] == 'verified'

    proposal
  end

  def blocked(code)
    { can_send: false, blocked_code: code }
  end
end
