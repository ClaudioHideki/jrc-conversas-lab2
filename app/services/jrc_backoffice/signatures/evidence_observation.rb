require 'digest'

# A trusted internal DTO from an authenticated, pinned provider connection.
# PDF hashes prove stored-byte integrity, not cryptographic equivalence between
# the unsigned original and signed PDF. Persistence/security admission is separate.
class JrcBackoffice::Signatures::EvidenceObservation
  BINDING_FIELDS = %w[account_id backoffice_request_id contract_id contract_version_id signer_roster_id authority_proposal_id
                      connection_id provider environment external_account_id pdf_sha256 version_digest roster_digest].freeze
  def initialize(delivery:, actor:)
    @delivery = delivery
    @actor = actor
    @access = JrcBackoffice::ContractAccess.new(account: delivery.account, actor: actor)
  end

  def call
    before = binding!
    observation = JrcBackoffice::Signatures::Gateway.new(connection: @delivery.connection).evidence(@delivery.external_id)
    fail!('PROVIDER_EVIDENCE_BINDING_INVALID') unless observation.fetch(:external_id) == @delivery.external_id &&
                                                      observation.fetch(:state) == 'completion_reported'

    signers = recipient_evidence!(observation.fetch(:signers))
    files = %i[signed_document certificate].index_with { |key| file!(observation.fetch(key)) }
    fail!('CONTRACT_SOURCE_CHANGED') unless binding! == before

    { binding: before, signers: signers, artifacts: files, observed_at: observation.fetch(:observed_at) }
  rescue KeyError, TypeError
    fail!('PROVIDER_RESPONSE_INVALID')
  end

  def verify_binding!(expected)
    fail!('CONTRACT_SOURCE_CHANGED') unless binding! == expected
  end

  def self.binding_data(delivery)
    delivery.snapshot.slice(*BINDING_FIELDS)
            .merge('delivery_id' => delivery.id, 'delivery_digest' => delivery.source_digest, 'external_id' => delivery.external_id)
  end

  private

  def binding!
    @delivery.reload
    fail!('ENVELOPE_NOT_BOUND') unless @delivery.external_id && @delivery.state.in?(%w[sent completion_reported])

    version = current_version!
    JrcBackoffice::AuthorityAccess.new(account: @delivery.account, actor: @actor).read_case!(@delivery.authority_proposal)
    bytes = version.pdf_blob.download
    fail!('CONTRACT_DOCUMENT_UNAVAILABLE') unless Digest::SHA256.hexdigest(bytes) == version.pdf_sha256

    self.class.binding_data(@delivery)
  end

  def current_version!
    request = @access.writable!(@access.request(@delivery.backoffice_request_id))
    contract = @access.contract!(request)
    versions = JrcBackoffice::ContractVersions.new(account: @delivery.account, actor: @actor, request_id: request.id).scope
    version = versions.where(contract_id: contract.id).order(number: :desc).first!
    expected = [@delivery.contract_version_id, *@delivery.snapshot.values_at('version_digest', 'pdf_sha256')]
    fail!('CONTRACT_SOURCE_CHANGED') unless expected == [version.id, version.source_digest, version.pdf_sha256]

    version
  end

  def recipient_evidence!(rows)
    expected = @delivery.snapshot.fetch('recipients')
    recipient_set!(rows, expected)

    expected.map do |person|
      row = rows.find { |item| item[:id] == person.fetch('position').to_s }
      recipient!(row, person)
    end
  end

  def recipient_set!(rows, expected)
    valid = rows.is_a?(Array) && rows.size == expected.size && rows.all?(Hash)
    fail!('SIGNATURE_RECIPIENT_MISMATCH') unless valid

    ids = rows.pluck(:id)
    fail!('SIGNATURE_RECIPIENT_MISMATCH') unless ids.all?(String) && ids.sort == expected.map { |row| row.fetch('position').to_s }.sort
  end

  def recipient!(row, person)
    identity = row[:email].to_s.strip.casecmp?(person.fetch('email').strip) &&
               row[:name].to_s.unicode_normalize(:nfc).strip == person.fetch('name').unicode_normalize(:nfc).strip
    fail!('SIGNATURE_RECIPIENT_MISMATCH') unless row[:completed] == true && identity

    time = signed_at!(row.fetch(:signed_at), person)
    { 'key' => person.fetch('key'), 'position' => person.fetch('position'), 'signed_at' => time.iso8601(6) }
  end

  def signed_at!(value, person)
    time = Time.iso8601(value)
    fail!('SIGNATURE_TIME_INVALID') unless time.between?(@delivery.created_at, Time.current)
    authority_at_signature!(time, person)
    time
  rescue ArgumentError, TypeError
    fail!('SIGNATURE_TIME_INVALID')
  end

  def authority_at_signature!(time, person)
    proof = @delivery.snapshot.fetch('authority_proofs').find { |row| row.fetch('signer_key') == person.fetch('key') }
    day = time.in_time_zone(Time.find_zone!(@delivery.snapshot.fetch('validity_timezone'))).to_date
    valid = proof && day >= Date.iso8601(proof.fetch('valid_from')) && (proof.fetch('no_expiry') || day <= Date.iso8601(proof.fetch('valid_until')))
    fail!('SIGNATURE_AUTHORITY_OUTSIDE_VALIDITY') unless valid
  end

  def file!(bytes)
    valid = bytes.is_a?(String) && bytes.b.start_with?('%PDF-') && bytes.bytesize.between?(5, JrcBackoffice::Documents::MAX_BYTES)
    fail!('SIGNATURE_FILE_INVALID') unless valid

    { bytes: bytes.b, sha256: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize, content_type: 'application/pdf' }
  end

  def fail!(code)
    raise JrcBackoffice::Signatures::DeliveryError, code
  end
end
