require 'rubygems/package'
require 'zlib'
require 'stringio'
require 'digest'

# An authenticated export of native immutable versions, not a new document registry.
# Provider status alone is deliberately never promoted to a signed artifact.
class JrcBackoffice::CompletionPackage
  class Changed < StandardError; end
  MAX_ITEMS = 100
  MAX_BYTES = 100.megabytes

  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
    @versions = JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: request_id)
  end

  def manifest
    @request = @access.request(@request_id)
    ensure_completed!

    contract = @request.contract_id && @access.contract!(@request)
    contracts = contract_entries
    files = document_entries + contracts
    missing = missing_entries(contract, contracts)
    result = request_manifest.merge(files: files, missing: missing, coverage: coverage(files, missing),
                                    contract_id: contract&.id,
                                    signature: contract && { status: contract.signature_status, artifact_available: false })
    @access.request(@request_id)
    @access.contract!(@request) if contract
    result
  end

  def download
    record = @access.request(@request_id)
    record.sales_order.with_lock('FOR SHARE') do
      record.with_lock('FOR SHARE') do
        captured = manifest
        available = captured[:files].select { |row| row[:availability] == 'available' }
        raise JrcBackoffice::CompletionReport::TooLarge if available.sum { |row| row[:byte_size] } > MAX_BYTES

        bytes = build_archive(captured, available)
        audit!(captured, Digest::SHA256.hexdigest(bytes))
        bytes
      end
    end
  end

  private

  def request_manifest
    { schema_version: 1, request_id: @request.id, request_number: @request.request_number,
      order_id: @request.sales_order_id, completed_at: @request.completed_at, responsible_id: @request.owner_id,
      signature_history: signature_history, history: history }
  end

  def missing_entries(contract, contracts)
    missing = missing_requirements + legacy_entries(@request)
    return missing unless contract

    missing << { kind: 'signed_contract', reason: 'VERSION_BOUND_SIGNED_ARTIFACT_UNAVAILABLE' }
    missing << { kind: 'contract_version', reason: 'PRESERVED_CONTRACT_VERSION_UNAVAILABLE' } if contracts.empty?
    missing + legacy_entries(contract)
  end

  def ensure_completed!
    raise JrcBackoffice::CompletionReport::NotCompleted unless @request.completed? && @request.stage == 'completed' && @request.completed_at
  end

  def coverage(files, missing)
    missing.empty? && files.all? { |row| row[:availability] == 'available' } ? 'available' : 'incomplete'
  end

  def legacy_entries(record)
    limited(record.documents_attachments.order(:id)).map do |attachment|
      { kind: 'legacy_attachment', attachment_id: attachment.id, reason: 'UNVERSIONED_ARTIFACT_NOT_EXPORTED' }
    end
  end

  def build_archive(captured, available)
    output = StringIO.new(''.b)
    Zlib::GzipWriter.wrap(output) do |gzip|
      Gem::Package::TarWriter.new(gzip) do |archive|
        available.each { |entry| add_file(archive, entry) }
        # Revalidate all current scopes, references, security decisions and completion after I/O.
        raise Changed unless manifest == captured

        data = JSON.pretty_generate(captured.as_json)
        archive.add_file_simple('manifest.json', 0o600, data.bytesize) { |file| file.write(data) }
      end
    end
    output.string
  end

  def add_file(archive, entry)
    bytes = file_bytes(entry)
    raise ActiveStorage::IntegrityError unless bytes.bytesize == entry[:byte_size] && Digest::SHA256.hexdigest(bytes) == entry[:sha256]

    archive.add_file_simple(entry[:path], 0o600, bytes.bytesize) { |file| file.write(bytes) }
  end

  def limited(rows)
    selected = rows.limit(MAX_ITEMS + 1).to_a
    raise JrcBackoffice::CompletionReport::TooLarge if selected.size > MAX_ITEMS

    selected
  end

  def document_entries
    limited(@request.document_versions.where(account_id: @access.account.id).order(:id)).map do |version|
      document_entry(version)
    end
  end

  def document_entry(version)
    scan = JrcBackoffice::DocumentSafety.new(version).current
    blob = version.file.blob
    extension = blob && JrcBackoffice::Documents::CONTENT_TYPES.key(blob.content_type)
    { kind: 'document', id: version.id, key: version.document_key, version: version.version,
      path: "documents/#{version.id}/v#{version.version}#{extension}", sha256: version.sha256, byte_size: blob ? blob.byte_size : 0,
      created_at: version.created_at, actor_id: version.uploaded_by_id, review_status: version.status,
      availability: scan&.clean? ? 'available' : 'blocked', scan_state: scan&.state || 'pending',
      decisions: limited(version.decisions.order(:id)).map { |row| row.slice('id', 'actor_id', 'status', 'created_at') } }
  end

  def contract_entries
    limited(@versions.scope.order(:id)).map do |version|
      { kind: 'contract_version', id: version.id, contract_id: version.contract_id, version: version.number,
        path: "contracts/#{version.contract_id}/v#{version.number}.pdf", sha256: version.pdf_sha256,
        byte_size: version.pdf_blob.byte_size, created_at: version.created_at, actor_id: version.created_by_id, availability: 'available' }
    end
  end

  def missing_requirements
    keys = @request.document_versions.where(account_id: @access.account.id).distinct.pluck(:document_key)
    JrcBackoffice::Documents.new(request: @request, actor: @access.actor).requirements.filter_map do |row|
      { kind: 'document', key: row['key'], reason: 'REQUIRED_DOCUMENT_UNAVAILABLE' } if row['required'] && keys.exclude?(row['key'])
    end
  end

  def history
    rows = JrcCrm::AuditEvent.where(account_id: @access.account.id, resource_type: @request.class.name, resource_id: @request.id)
                             .where.not(event_type: %w[backoffice_completion_package_accessed backoffice_completion_report_accessed])
    limited(rows.order(:id)).map { |row| row.slice('id', 'event_type', 'actor_type', 'actor_id', 'created_at') }
  end

  def file_bytes(entry)
    return @versions.download!(entry[:id]).last if entry[:kind] == 'contract_version'

    version = @request.document_versions.where(account_id: @access.account.id).find(entry[:id])
    JrcBackoffice::DocumentSafety.new(version).bytes!
  end

  def signature_history
    reader = JrcBackoffice::Signatures::History.new(account: @access.account, actor: @access.actor, request_id: @request_id)
    rows = signature_pages { |page| reader.call(page: page) }
    rows.map do |row|
      events = signature_pages { |page| reader.show(row.fetch('id'), page: page) }
      row.merge('events' => events)
    end
  end

  def signature_pages
    first = yield(1)
    raise JrcBackoffice::CompletionReport::TooLarge if first[:meta][:total] > MAX_ITEMS

    first[:data] + (2..first[:meta][:pages]).flat_map { |page| yield(page)[:data] }
  end

  def audit!(captured, digest)
    JrcCrm::AuditEvent.create!(account: @access.account, actor_type: 'User', actor_id: @access.actor.id,
                               event_type: 'backoffice_completion_package_accessed', resource_type: @request.class.name,
                               resource_id: @request.id, from_value: {}, to_value: {},
                               metadata: { schema_version: 1, format: 'tar.gz', sha256: digest, coverage: captured[:coverage],
                                           versions: captured[:files].map { |entry| entry.slice(:kind, :id, :sha256, :availability) } })
  end
end
