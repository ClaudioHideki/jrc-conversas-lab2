# Checks the admitted legal context again at dispatch. This does not reselect
# the provider default or silently replace the policies pinned at admission.
class JrcBackoffice::Signatures::DispatchContext
  def initialize(delivery:)
    @delivery = delivery
    @access = JrcBackoffice::ContractAccess.new(account: delivery.account, actor: delivery.created_by)
  end

  def access!
    request = @access.writable!(@access.request(@delivery.backoffice_request_id))
    contract = @access.contract!(request)
    raise JrcBackoffice::Signatures::DeliveryError, 'CONTRACT_SOURCE_CHANGED' unless contract.id == @delivery.contract_id

    JrcBackoffice::AuthorityAccess.new(account: @delivery.account, actor: @delivery.created_by).read_case!(@delivery.authority_proposal)
    request
  end

  def verify!
    access!
    status = JrcBackoffice::AuthorityStatus.new(proposal: @delivery.authority_proposal, actor: @delivery.created_by).call(verify: true)
    unless status[:status] == 'verified' && matching_approvals? && within_original_validity?
      raise JrcBackoffice::Signatures::DeliveryError, 'AUTHORITY_APPROVAL_REQUIRED'
    end

    bytes = @delivery.contract_version.pdf_blob.download
    unless Digest::SHA256.hexdigest(bytes) == @delivery.snapshot['pdf_sha256']
      raise JrcBackoffice::Signatures::DeliveryError,
            'CONTRACT_DOCUMENT_UNAVAILABLE'
    end

    access!
    bytes
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    raise JrcBackoffice::Signatures::DeliveryError, 'CONTRACT_DOCUMENT_UNAVAILABLE'
  end

  private

  def matching_approvals?
    access = JrcBackoffice::AuthorityAccess.new(account: @delivery.account, actor: @delivery.created_by)
    rows = access.approval_requests(@delivery.authority_proposal).where(request_key: "authority:#{@delivery.authority_proposal_id}").order(:id).to_a
    expected = @delivery.snapshot.fetch('authority_approvals')
    rows.length == expected.length && rows.any? && rows.zip(expected).all? { |record, fact| same_approval?(record, fact) }
  end

  def same_approval?(record, fact)
    record.lock!('FOR SHARE')
    fields = %w[id policy_version_id fingerprint cycle]
    record.attributes.values_at(*fields) == fact.values_at(*fields) && record.expires_at == Time.iso8601(fact.fetch('expires_at')) &&
      record.decisions.where(cycle: record.cycle, decision: 'approved').order(:id).pluck(:id) == fact['decision_ids']
  end

  def within_original_validity?
    source = @delivery.snapshot
    today = Time.current.in_time_zone(source.fetch('validity_timezone')).to_date
    source.fetch('authority_proofs').all? do |row|
      Date.iso8601(row.fetch('valid_from')) <= today && (row.fetch('no_expiry') || Date.iso8601(row.fetch('valid_until')) >= today)
    end
  end
end
