# A file's availability is documentary evidence, never legal approval or signature authority.
class JrcRelationship::DocumentRequirements
  MAX_ENTRIES = 50
  FIELDS = %w[code title category].freeze

  def self.validate!(entries)
    valid = entries.is_a?(Array) && entries.size <= MAX_ENTRIES && entries.all? { |entry| valid_entry?(entry) }
    valid &&= entries.pluck('code').uniq.size == entries.size
    raise ArgumentError, 'Required documents need up to 50 unique codes, bounded titles and native categories' unless valid
  end

  def self.valid_entry?(entry)
    entry.is_a?(Hash) && entry.keys.sort == FIELDS.sort && valid_code?(entry['code']) && valid_title?(entry['title']) &&
      JrcRelationship::CustomerDocument::CATEGORIES.include?(entry['category'])
  end

  def self.valid_code?(code)
    code.is_a?(String) && code.match?(/\A[a-z][a-z0-9_-]{0,59}\z/)
  end

  def self.valid_title?(title)
    title.is_a?(String) && title.strip.length.between?(1, 120)
  end
  private_class_method :valid_entry?, :valid_code?, :valid_title?

  def initialize(context)
    @context = context
  end

  def validate_link!(document, key)
    return nil if key.blank?
    return key if document.persisted? && document.requirement_key == key

    configuration = @context.configuration(document.assignment)
    entry = configuration.effective_rules['required_documents'].find { |item| item['code'] == key }
    raise ArgumentError, 'Requirement does not exist in the current catalog or category' unless entry && entry['category'] == document.category

    key
  end

  def call(assignment_id:)
    service = JrcRelationship::CustomerDocuments.new(@context)
    scope = service.scope
    assignment = @context.assignment(assignment_id)
    configuration = @context.configuration(assignment)
    entries = configuration.effective_rules['required_documents']
    documents = scope.where(assignment_id: assignment.id, status: 'active', requirement_key: entries.pluck('code')).index_by(&:requirement_key)
    versions = service.latest_versions(document_ids: documents.values.map(&:id))
    { scope_key: configuration.scope_key, configuration_version: configuration.version,
      entries: entries.map { |entry| project(entry, documents[entry['code']], versions) } }
  end

  private

  def project(entry, document, versions)
    version = document && versions[document.id]
    entry.merge(state: state(entry, document, version), document_id: document&.id,
                version_id: version&.id, version_number: version&.number)
  end

  def available_file?(version)
    version.file.attached? && JrcServiceDesk::AttachmentScanner.clean?(version.file.blob)
  end

  def state(entry, document, version)
    return 'missing' unless version
    return 'category_mismatch' unless document.category == entry['category']
    return 'expired' if version.valid_until && version.valid_until < Date.current
    return 'quarantined' unless available_file?(version)

    'file_available'
  end
end
