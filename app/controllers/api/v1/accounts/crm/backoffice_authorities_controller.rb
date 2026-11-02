class Api::V1::Accounts::Crm::BackofficeAuthoritiesController < Api::V1::Accounts::Crm::BaseController
  prepend_before_action do
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end
  rescue_from JrcBackoffice::AuthorityProposals::Changed do
    render json: { code: 'AUTHORITY_CONTEXT_CHANGED' }, status: :conflict
  end
  rescue_from ArgumentError, KeyError do |error|
    render json: { code: 'AUTHORITY_INVALID_INPUT', message: error.message }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::DocumentSafety::NotClean, ActiveStorage::IntegrityError, ActiveStorage::FileNotFoundError do
    render json: { code: 'AUTHORITY_EVIDENCE_UNAVAILABLE' }, status: :unprocessable_entity
  end
  rescue_from ActiveRecord::Encryption::Errors::Decryption do
    render json: { code: 'AUTHORITY_CONTEXT_UNAVAILABLE' }, status: :unprocessable_entity
  end

  def index
    render json: JrcBackoffice::AuthorityOverview.new(account: Current.account, actor: Current.user,
                                                      request_id: params[:backoffice_request_id]).call(page: params[:page])
  end

  def show
    render json: JrcBackoffice::AuthorityCase.new(proposal: proposal, actor: Current.user).call
  end

  def create
    record = JrcBackoffice::AuthorityProposals.new(account: Current.account, actor: Current.user,
                                                   request_id: params[:backoffice_request_id]).create!(**authority_params.to_h.symbolize_keys)
    render json: JrcBackoffice::AuthorityCase.new(proposal: record, actor: Current.user).call, status: :created
  end

  def contract_pdf
    version, bytes = evidence.contract_pdf!
    send_data bytes, filename: "contrato-v#{version.number}.pdf", type: 'application/pdf', disposition: 'attachment'
  end

  def document
    version, bytes = evidence.document!(params[:document_version_id])
    send_data bytes, filename: version.file.filename.to_s, type: version.file.content_type, disposition: 'attachment'
  end

  private

  def proposal
    JrcBackoffice::AuthorityProposal.where(account_id: Current.account.id,
                                           backoffice_request_id: params[:backoffice_request_id]).find(params[:proposal_id])
  end

  def evidence
    JrcBackoffice::AuthorityEvidence.new(proposal: proposal, actor: Current.user)
  end

  def authority_params
    proof_fields = [:signer_key, :basis, :reason, :valid_from, :valid_until, :no_expiry, { document_version_ids: [] }]
    params.require(:authority_proposal).permit(:version_id, :expected_revision, :expected_source_digest, :change_reason, :idempotency_key,
                                               proofs: proof_fields)
  end
end
