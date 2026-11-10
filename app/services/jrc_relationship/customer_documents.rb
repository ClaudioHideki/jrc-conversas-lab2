class JrcRelationship::CustomerDocuments
  CONTENT_TYPES = %w[application/pdf image/png image/jpeg text/plain
                     application/vnd.openxmlformats-officedocument.wordprocessingml.document].freeze
  MAX_BYTES = 10.megabytes
  EXTENSIONS = %w[.pdf .png .jpg .jpeg .txt .docx].freeze

  def initialize(context)
    @context = context
  end

  def scope
    raise Pundit::NotAuthorizedError unless @context.policy.documents_view?

    JrcRelationship::DocumentAccess.scope(@context,
      JrcRelationship::CustomerDocument.where(account_id: @context.account.id, assignment_id: @context.assignments.select(:id)))
  end

  def latest_versions(document_ids:)
    documents = scope.where(id: document_ids)
    return {} if document_ids.empty?

    JrcRelationship::DocumentVersion.where(account_id: @context.account.id, document_id: documents.pluck(:id))
                                    .select('DISTINCT ON (document_id) jrc_relationship_document_versions.*')
                                    .order(:document_id, number: :desc).includes(:uploaded_by, file_attachment: :blob).index_by(&:document_id)
  end

  def upload!(assignment_id:, attributes:, upload:, document_id: nil)
    permitted = document_id ? @context.policy.documents_replace? : @context.policy.documents_upload?
    raise Pundit::NotAuthorizedError unless permitted

    type = validate_upload!(upload)
    assignment = @context.assignment(assignment_id)
    document = document_id ? scope.find(document_id) : JrcRelationship::CustomerDocument.new(account: @context.account, assignment: assignment)
    raise ActiveRecord::RecordNotFound unless document.assignment_id == assignment.id

    version = nil
    assignment.with_lock do
      @context = JrcRelationship::Context.new(@context.member)
      @context.assignment(assignment.id)
      document.lock! if document.persisted?
      raise ArgumentError, 'Archived document cannot receive a version' if document.status == 'archived'

      assign_new_document!(document, attributes) unless document_id
      JrcRelationship::DocumentAccess.authorize!(@context, document, document_id ? 'replace' : 'upload')
      document.save!
      version = create_version!(document, attributes, upload, type)
    end
    JrcRelationship::DocumentScanJob.perform_later(version.id)
    document
  end

  def download!(document_id:, version_id:)
    document = scope.find(document_id)
    JrcRelationship::DocumentAccess.authorize!(@context, document, 'download')
    version = document.versions.where(account_id: @context.account.id).find(version_id)
    bytes = JrcServiceDesk::AttachmentScanner.download(version.file.blob)
    current_context = JrcRelationship::Context.new(@context.member)
    document.reload
    JrcRelationship::DocumentAccess.authorize!(current_context, document, 'download')
    # The native scanner is rechecked after bytes are read and before returning them.
    raise JrcServiceDesk::AttachmentScanError unless JrcServiceDesk::AttachmentScanner.clean?(version.file.blob.reload)
    current_context.audit!(document, after: { version_id: version.id, version: version.number }, action: 'document_downloaded')
    [version.file.blob, bytes]
  end

  private

  def assign_new_document!(document, attributes)
    document.assign_attributes(attributes.slice('title', 'category', 'confidentiality'))
    raise ArgumentError, 'Choose an explicit document confidentiality' unless %w[operational restricted].include?(document.confidentiality)
    document.requirement_key = JrcRelationship::DocumentRequirements.new(@context).validate_link!(document, attributes['requirement_key'])
  end

  def validate_upload!(upload)
    raise ArgumentError, 'Send a file of at most 10 MiB' unless upload.respond_to?(:tempfile) && upload.size.between?(1, MAX_BYTES)

    type = Marcel::MimeType.for(upload.tempfile, name: upload.original_filename)
    unless CONTENT_TYPES.include?(type) && EXTENSIONS.include?(File.extname(upload.original_filename.to_s).downcase)
      raise ArgumentError, 'Unsupported document type or extension'
    end

    type
  end

  def create_version!(document, attributes, upload, type)
    version = document.versions.create!(account: @context.account, uploaded_by: @context.user,
                                        number: document.versions.maximum(:number).to_i + 1,
                                        valid_until: attributes['valid_until'].presence, change_reason: attributes.fetch('change_reason'))
    upload.tempfile.rewind
    version.file.attach(io: upload.tempfile, filename: upload.original_filename, content_type: type, identify: false)
    @context.audit!(document, after: { version: version.number, version_id: version.id, valid_until: version.valid_until },
                              action: 'document_uploaded')
    version
  end
end
