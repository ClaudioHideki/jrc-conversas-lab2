class JrcBackoffice::Documents
  MAX_BYTES = 20.megabytes
  CONTENT_TYPES = { '.pdf' => 'application/pdf', '.png' => 'image/png', '.jpg' => 'image/jpeg', '.jpeg' => 'image/jpeg' }.freeze

  def initialize(request:, actor:)
    @request, @actor = request, actor
  end

  def requirements
    configured = Array(@request.metadata['document_checklist']).select { |row| row['source'] == 'manual' }
    legacy = Array(@request.metadata['required_documents']).map do |key|
      { 'key' => key, 'label' => key, 'required' => true, 'blocking' => true, 'source' => 'manual' }
    end
    (configured + legacy).uniq { |row| row['key'] }
  end

  def upload!(key:, file:, idempotency_key:)
    raise ArgumentError, 'Selecione um requisito documental configurado.' unless requirements.any? { |row| row['key'] == key }
    raise ArgumentError, 'Identificador do envio inválido.' unless idempotency_key.to_s.match?(/\A[\w-]{16,100}\z/)

    content_type = validate_file!(file)
    digest = Digest::SHA256.file(file.tempfile.path).hexdigest
    @request.with_lock do
      writable!
      existing = versions.find_by(idempotency_key: idempotency_key)
      if existing
        unless existing.document_key == key && existing.sha256 == digest
          raise ArgumentError, 'Identificador de envio já utilizado para outro documento.'
        end

        return existing
      end
      record = versions.new(account: @request.account, uploaded_by: @actor, document_key: key,
        version: versions.where(document_key: key).maximum(:version).to_i + 1, sha256: digest, idempotency_key: idempotency_key)
      blob = ActiveStorage::Blob.create_and_upload!(io: file.tempfile, filename: file.original_filename,
        content_type: content_type, identify: false)
      record.file.attach(blob)
      record.save!
      update_status!(key, 'received')
      audit!('backoffice_document_version_uploaded', version_id: record.id, document_key: key, version: record.version)
      record
    end
  end

  def reflect_analysis!(version)
    @request.with_lock do
      latest = versions.where(document_key: version.document_key).order(version: :desc).first
      return unless latest.id == version.id

      update_status!(version.document_key, version.status)
      audit!('backoffice_document_analyzed', version_id: version.id, analysis_id: version.analysis.id, status: version.status)
    end
  end

  def decide!(version:, status:, reason:)
    @request.with_lock do
      writable!
      latest = versions.where(document_key: version.document_key).order(version: :desc).first
      raise ArgumentError, 'A versão foi substituída. Analise a versão atual.' unless latest.id == version.id
      raise ArgumentError, 'Aguarde a pré-análise documental.' unless version.analysis

      decision = version.decisions.create!(actor: @actor, status: status, reason: reason)
      update_status!(version.document_key, decision.status)
      audit!('backoffice_document_decided', version_id: version.id, decision_id: decision.id, status: decision.status)
      decision
    end
  end

  private

  def versions
    @request.document_versions
  end

  def writable!
    raise ArgumentError, 'Reabra a solicitação antes de alterar seus documentos.' if @request.status.in?(%w[completed canceled rejected])
  end

  def validate_file!(file)
    raise ArgumentError, 'Envie um PDF, PNG ou JPEG de até 20 MB.' unless file.respond_to?(:tempfile) && file.size.positive? && file.size <= MAX_BYTES

    type = CONTENT_TYPES[File.extname(file.original_filename).downcase]
    file.tempfile.rewind
    magic = file.tempfile.read(8)
    valid = case type
            when 'application/pdf' then magic.start_with?('%PDF-')
            when 'image/png' then magic == "\x89PNG\r\n\x1a\n".b
            when 'image/jpeg' then magic.start_with?("\xff\xd8\xff".b)
            else false
            end
    raise ArgumentError, 'O conteúdo do arquivo não corresponde a um formato permitido.' unless valid

    type
  ensure
    file.tempfile.rewind if file.respond_to?(:tempfile)
  end

  def update_status!(key, status)
    data = @request.metadata.deep_dup
    data['document_statuses'] ||= {}
    data['document_statuses'][key] = status
    @request.update!(metadata: data)
    JrcCrm::BackofficeDocumentChecklist.new(request: @request, actor: @actor).sync! if @request.fulfillment?
  end

  def audit!(event, data)
    JrcCrm::AuditEvent.create!(account: @request.account, actor_type: 'User', actor_id: @actor.id, event_type: event,
      resource_type: @request.class.name, resource_id: @request.id, from_value: {}, to_value: data, metadata: { source: 'backoffice_documents' })
  end
end
