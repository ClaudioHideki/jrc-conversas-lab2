require 'openssl'
require 'digest'

# The proposal pins references/hashes, not a new person/document registry. Its
# native Central context changes when the legal source, people, evidence or
# declared validity changes. Operational progress is not a legal revision.
class JrcBackoffice::AuthoritySource
  def initialize(proposal:, actor:)
    @proposal = proposal
    @actor = actor
    @access = JrcBackoffice::AuthorityAccess.new(account: proposal.account, actor: actor)
  end

  def self.digest(data)
    key = Rails.application.key_generator.generate_key('jrc-contract-signing-authority-v1', 32)
    OpenSSL::HMAC.hexdigest('SHA256', key, JrcServiceDesk::CanonicalJson.dump(data))
  end

  def self.build(version:, proofs:)
    documents = JrcBackoffice::AuthorityDocuments.new(account: version.account, request_id: version.backoffice_request_id)
    bindings = documents.capture(proofs)
    documents.verify!(proofs, expected: bindings)
    { 'format_version' => 1, 'account_id' => version.account_id, 'contract_id' => version.contract_id,
      'backoffice_request_id' => version.backoffice_request_id, 'contract_version_id' => version.id,
      'signer_roster_id' => version.signer_roster_id, 'version_digest' => version.source_digest,
      'pdf_sha256' => version.pdf_sha256, 'roster_digest' => version.signer_roster.source_digest,
      'proofs' => proofs, 'document_bindings' => bindings }
  end

  def current
    @access.read_case!(@proposal)
    source = @proposal.snapshot
    documents = JrcBackoffice::AuthorityDocuments.new(account: @proposal.account, request_id: @proposal.backoffice_request_id)
    bindings = documents.capture(source.fetch('proofs'))
    integrity = current_facts(source, bindings)
    @access.read_case!(@proposal)
    { current: integrity.values.all?, facts: integrity,
      context_digest: self.class.digest('proposal_digest' => @proposal.source_digest, 'facts' => integrity, 'document_bindings' => bindings) }
  end

  def verify!
    context = current
    raise JrcApprovals::Error, 'AUTHORITY_CONTEXT_STALE' unless context[:current]

    source = @proposal.snapshot
    JrcBackoffice::AuthorityDocuments.new(account: @proposal.account, request_id: @proposal.backoffice_request_id)
                                     .verify!(source.fetch('proofs'), expected: source.fetch('document_bindings'))
    bytes = @proposal.contract_version.pdf_blob.download
    raise ActiveStorage::IntegrityError unless Digest::SHA256.hexdigest(bytes) == @proposal.contract_version.pdf_sha256
    raise JrcApprovals::Error, 'AUTHORITY_CONTEXT_STALE' unless current == context

    true
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    raise JrcApprovals::Error, 'AUTHORITY_EVIDENCE_UNAVAILABLE'
  end

  private

  def current_facts(source, bindings)
    latest = JrcBackoffice::AuthorityProposal.where(account_id: @proposal.account_id,
                                                    contract_version_id: @proposal.contract_version_id).order(revision: :desc).first
    JrcBackoffice::AuthorityIntegrity.new(version: @proposal.contract_version, actor: @actor).call.merge(
      proposal_current: latest&.id == @proposal.id,
      documents_current: bindings == source.fetch('document_bindings') && bindings.all? { |row| row['ready'] },
      validity_current: valid_today?(source.fetch('proofs'))
    )
  end

  def valid_today?(proofs)
    Time.use_zone(Time.find_zone(@proposal.account.reporting_timezone) || 'UTC') do
      today = Date.current
      proofs.all? do |row|
        Date.iso8601(row.fetch('valid_from')) <= today && (row.fetch('no_expiry') || Date.iso8601(row.fetch('valid_until')) >= today)
      end
    end
  end
end
