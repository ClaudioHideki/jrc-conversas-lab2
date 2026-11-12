require 'openssl'

# Internal facts only. Provider JSON/authentication belongs in the connector.
class JrcBackoffice::Signatures::DeliverySnapshot
  def self.digest(data)
    key = Rails.application.key_generator.generate_key('jrc-signature-admission-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JrcServiceDesk::CanonicalJson.dump(data))
  end

  def self.capture(version:, proposal:, connection:, actor:)
    status = JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call(verify: true)
    raise JrcBackoffice::Signatures::DeliveryError, 'AUTHORITY_APPROVAL_REQUIRED' unless status[:status] == 'verified'

    data = header(version, proposal, connection).merge(
      'admitted_at' => Time.current.iso8601(6), 'validity_timezone' => Time.find_zone(version.account.reporting_timezone)&.name || 'UTC',
      'authority_digest' => proposal.source_digest, 'authority_proofs' => proposal.snapshot.fetch('proofs'),
      'authority_approvals' => approval_facts(proposal, actor), 'recipients' => recipients(version)
    )
    final = JrcBackoffice::AuthorityStatus.new(proposal: proposal, actor: actor).call(verify: true)
    raise JrcBackoffice::Signatures::DeliveryError, 'AUTHORITY_APPROVAL_REQUIRED' unless final == status

    data
  end

  def self.approval_facts(proposal, actor)
    access = JrcBackoffice::AuthorityAccess.new(account: proposal.account, actor: actor)
    access.approval_requests(proposal).where(request_key: "authority:#{proposal.id}").order(:id).map do |record|
      record.lock!('FOR SHARE')
      approval_fact(record)
    end
  end
  private_class_method :approval_facts

  def self.recipients(version)
    version.signer_roster.snapshot.fetch('signers').select { |row| row.fetch('required') }.map do |row|
      row.slice('key', 'position', 'party', 'contact_id', 'company_id', 'name', 'email', 'anchor', 'required')
    end
  end
  private_class_method :recipients

  def self.header(version, proposal, connection)
    { 'format_version' => 1, 'account_id' => version.account_id, 'contract_id' => version.contract_id,
      'backoffice_request_id' => version.backoffice_request_id, 'contract_version_id' => version.id,
      'signer_roster_id' => version.signer_roster_id, 'authority_proposal_id' => proposal.id, 'connection_id' => connection.id,
      'provider' => connection.provider, 'environment' => connection.environment, 'external_account_id' => connection.external_account_id,
      'connection_revision' => connection.revision, 'pdf_sha256' => version.pdf_sha256, 'version_digest' => version.source_digest,
      'roster_digest' => version.signer_roster.source_digest }
  end
  private_class_method :header

  def self.approval_fact(record)
    { 'id' => record.id, 'policy_version_id' => record.policy_version_id, 'fingerprint' => record.fingerprint,
      'cycle' => record.cycle, 'expires_at' => record.expires_at.iso8601(6),
      'decision_ids' => record.decisions.where(cycle: record.cycle, decision: 'approved').order(:id).pluck(:id) }
  end
  private_class_method :approval_fact
end
