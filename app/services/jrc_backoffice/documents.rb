require 'stringio'

class JrcBackoffice::Documents
  class Conflict < StandardError; end

  MAX_BYTES = 20.megabytes
  CONTENT_TYPES = { '.pdf' => 'application/pdf', '.png' => 'image/png', '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg' }.freeze
  SignatureFile = Struct.new(:tempfile, :original_filename)

  def initialize(request:, actor:)
    @request = request
    @actor = actor
  end

  def requirements
    configured = Array(@request.metadata['document_checklist']).select { |row| row['source'] == 'manual' }
    legacy = Array(@request.metadata['required_documents']).map do |key|
      { 'key' => key, 'label' => key, 'required' => true, 'blocking' => true, 'source' => 'manual' }
    end
    (configured + legacy + JrcBackoffice::Requirements.documents(@request)).uniq { |row| row['key'] }
  end

  def upload!(key:, file:, idempotency_key:)
    @pending_blob = nil
    validate_upload!(key, idempotency_key)
    content_type = validate_file!(file)
    digest = Digest::SHA256.file(file.tempfile.path).hexdigest
    @request.with_lock(requires_new: true) do
      writable!
      replay_version!(key, digest, idempotency_key) ||
        persist_upload!(key: key, file: file, idempotency_key: idempotency_key, digest: digest, content_type: content_type)
    end
  rescue StandardError
    JrcBackoffice::PrivateBlob.clean_uncommitted(@pending_blob, marker: 'jrc_backoffice_document_upload')
    raise
  ensure
    @pending_blob = nil
  end

  # System artifacts are not editable checklist requirements. They retain the
  # native immutable version, private blob, scan job and rollback protections.
  def receive_signature_file!(delivery:, kind:, artifact:)
    @pending_blob = nil
    input = signature_file_input!(delivery, kind, artifact)
    @request.with_lock do
      writable!
      replay_version!(input[:key], input[:digest], input[:idempotency]) || persist_signature_file!(delivery, kind, input)
    end
  rescue StandardError
    JrcBackoffice::PrivateBlob.clean_uncommitted(@pending_blob, marker: 'jrc_backoffice_document_upload')
    raise
  ensure
    @pending_blob = nil
  end

  # Technical job projection only. It cannot reuse a user's document authority
  # or create a human decision; interactive commands still require writable!.
  def reflect_analysis!(version)
    raise Pundit::NotAuthorizedError unless @actor.nil?

    @request.with_lock do
      current = versions.find(version.id)
      latest = versions.where(document_key: current.document_key).order(version: :desc).first
      next unless latest.id == current.id && current.analysis
      next if @request.status.in?(%w[completed canceled rejected])

      # Recheck tenant, feature, current security observation and exact bytes
      # after parsing, before changing the operational projection.
      JrcBackoffice::DocumentSafety.new(current).bytes!
      update_status!(current.document_key, current.status)
      audit!('backoffice_document_analyzed', version_id: current.id, analysis_id: current.analysis.id, status: current.status)
    end
  end

  def decide!(version:, status:, reason:, expires_on: JrcBackoffice::DocumentValidity::UNSPECIFIED,
              expected_decision_id: JrcBackoffice::DocumentValidity::UNSPECIFIED)
    @request.with_lock do
      writable!
      validate_review!(version, status)
      previous = version.current_decision
      JrcBackoffice::DocumentValidity.revision!(expected_decision_id, previous&.id, validity: expires_on)
      expiration = JrcBackoffice::DocumentValidity.resolve(value: expires_on, previous: previous&.expires_on)
      zone = expiration && (expires_on.equal?(JrcBackoffice::DocumentValidity::UNSPECIFIED) ? previous.validity_timezone :
        (Time.find_zone(@request.account.reporting_timezone) || Time.find_zone!('UTC')).tzinfo.identifier)
      if status == 'approved' && expiration && expiration < Time.current.in_time_zone(Time.find_zone!(zone)).to_date
        raise ArgumentError, 'An expired document cannot be approved; send a new valid version'
      end
      decision = version.decisions.create!(actor: @actor, status: status, reason: reason,
                                           expires_on: expiration, validity_timezone: zone)
      update_status!(version.document_key, version.status)
      writable!
      audit!('backoffice_document_decided', version_id: version.id, decision_id: decision.id, status: decision.status,
        expires_on: decision.expires_on&.iso8601, validity_timezone: decision.validity_timezone)
      decision
    end
  end

  private

  def signature_file_input!(delivery, kind, artifact)
    raise ArgumentError, 'Unsupported signature artifact' unless %i[signed_document certificate].include?(kind)
    raise Pundit::NotAuthorizedError unless delivery.account_id == @request.account_id && delivery.backoffice_request_id == @request.id

    bytes = artifact.fetch(:bytes)
    digest = Digest::SHA256.hexdigest(bytes)
    raise ActiveStorage::IntegrityError unless bytes.b.start_with?('%PDF-') && bytes.bytesize <= MAX_BYTES && digest == artifact.fetch(:sha256)

    key = "signature_delivery_#{delivery.id}_#{kind}"
    { key: key, digest: digest, idempotency: Digest::SHA256.hexdigest("#{key}:#{digest}"),
      file: SignatureFile.new(StringIO.new(bytes), "#{kind}.pdf") }
  end

  def persist_signature_file!(delivery, kind, input)
    key = input.fetch(:key)
    record = versions.new(account: @request.account, uploaded_by: @actor, document_key: key,
      version: versions.where(document_key: key).maximum(:version).to_i + 1, sha256: input.fetch(:digest), idempotency_key: input.fetch(:idempotency))
    attach_upload!(record, input.fetch(:file), 'application/pdf')
    record.save!
    audit!('backoffice_signature_artifact_uploaded', version_id: record.id, delivery_id: delivery.id, kind: kind, sha256: input.fetch(:digest))
    record
  end

  def validate_upload!(key, idempotency_key)
    raise ArgumentError, 'Selecione um requisito documental configurado.' unless requirements.any? { |row| row['key'] == key }
    raise ArgumentError, 'Identificador do envio inválido.' unless idempotency_key.to_s.match?(/\A[\w-]{16,100}\z/)
  end

  def replay_version!(key, digest, idempotency_key)
    existing = versions.find_by(idempotency_key: idempotency_key)
    return unless existing

    matches = existing.document_key == key && existing.sha256 == digest
    raise ArgumentError, 'Identificador de envio já utilizado para outro documento.' unless matches

    existing
  end

  def persist_upload!(key:, file:, idempotency_key:, digest:, content_type:)
    record = versions.new(account: @request.account, uploaded_by: @actor, document_key: key,
                          version: versions.where(document_key: key).maximum(:version).to_i + 1, sha256: digest, idempotency_key: idempotency_key)
    attach_upload!(record, file, content_type)
    record.save!
    update_status!(key, 'received')
    audit!('backoffice_document_version_uploaded', version_id: record.id, document_key: key, version: record.version)
    record
  end

  def attach_upload!(record, file, content_type)
    @pending_blob = JrcBackoffice::PrivateBlob.upload_owned(io: file.tempfile, filename: file.original_filename,
                                                            content_type: content_type, marker: 'jrc_backoffice_document_upload')
    record.new_upload_blob = @pending_blob
    writable!
    record.file.attach(@pending_blob)
  end

  def validate_review!(version, status)
    latest = versions.where(document_key: version.document_key).order(version: :desc).first
    raise ArgumentError, 'A versão foi substituída. Analise a versão atual.' unless latest.id == version.id

    safety = JrcBackoffice::DocumentSafety.new(version)
    raise ArgumentError, 'Aguarde a verificação documental.' unless version.analysis || safety.current
    return unless status == 'approved'

    safety.bytes!
    raise ArgumentError, 'Aguarde a pré-análise documental.' unless version.analysis

    writable!
  end

  def versions
    @request.document_versions.where(account_id: @request.account_id)
  end

  def writable!
    JrcBackoffice::ContractAccess.new(account: @request.account, actor: @actor).request(@request.id)
    raise ArgumentError, 'Reabra a solicitação antes de alterar seus documentos.' if @request.status.in?(%w[completed canceled rejected])
  end

  def validate_file!(file)
    raise ArgumentError, 'Envie um PDF, PNG ou JPEG de até 20 MB.' unless file.respond_to?(:tempfile) && file.size.positive? && file.size <= MAX_BYTES

    type = CONTENT_TYPES[File.extname(file.original_filename).downcase]
    file.tempfile.rewind
    magic = file.tempfile.read(8)
    raise ArgumentError, 'O conteúdo do arquivo não corresponde a um formato permitido.' unless matching_file?(type, magic)

    type
  ensure
    file.tempfile.rewind if file.respond_to?(:tempfile)
  end

  def matching_file?(type, magic)
    case type
    when 'application/pdf' then magic.start_with?('%PDF-')
    when 'image/png' then magic == "\x89PNG\r\n\x1a\n".b
    when 'image/jpeg' then magic.start_with?("\xff\xd8\xff".b)
    else false
    end
  end

  def update_status!(key, status)
    data = @request.metadata.deep_dup
    data['document_statuses'] ||= {}
    data['document_statuses'][key] = status
    @request.update!(metadata: data)
    JrcCrm::BackofficeDocumentChecklist.new(request: @request, actor: @actor).sync! if @request.fulfillment?
  end

  def audit!(event, data)
    JrcCrm::AuditEvent.create!(account: @request.account, actor_type: @actor ? 'User' : 'System', actor_id: @actor&.id, event_type: event,
                               resource_type: @request.class.name, resource_id: @request.id, from_value: {}, to_value: data,
                               metadata: { source: 'backoffice_documents' })
  end
end
