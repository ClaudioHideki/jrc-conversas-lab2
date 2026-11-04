# Responsibility is explicit metadata, independent of uploader, portfolio ownership and signature authority.
class JrcRelationship::DocumentMetadata
  def initialize(context)
    @context = context
  end

  def responsibles(document_id:)
    authorize!
    JrcRelationship::CustomerDocuments.new(@context).scope.find(document_id)
    @context.assignable_users
  end

  def update!(document_id:, attributes:)
    authorize!
    document = JrcRelationship::CustomerDocuments.new(@context).scope.find(document_id)
    reason = change_reason!(attributes.fetch('reason'))

    document.with_lock do
      authorize_current!(document)
      validate_revision!(document, attributes.fetch('revision'))

      before = document.attributes.slice('responsible_id', 'status', 'requirement_key')
      assign_responsible!(document, attributes['responsible_id']) if attributes.key?('responsible_id')
      document.status = attributes['status'] if attributes.key?('status')
      assign_requirement!(document, attributes['requirement_key']) if attributes.key?('requirement_key')
      document.save!
      audit_change!(document, before, reason)
    end
    document
  end

  private

  def change_reason!(value)
    raise ArgumentError, 'Explain the metadata change (1-500 characters)' unless value.is_a?(String) && value.strip.length.between?(1, 500)

    value.strip
  end

  def authorize_current!(document)
    @context = JrcRelationship::Context.new(@context.member)
    authorize!
    @context.assignment(document.assignment_id)
  end

  def validate_revision!(document, value)
    revision = Integer(value.to_s, 10)
    raise ActiveRecord::StaleObjectError.new(document, 'update') unless revision == document.lock_version
  end

  def audit_change!(document, before, reason)
    changes = document.attributes.slice('responsible_id', 'status', 'requirement_key').merge('reason' => reason)
    @context.audit!(document, before: before, after: changes, action: 'document_metadata_updated')
  end

  def authorize!
    raise Pundit::NotAuthorizedError unless @context.policy.documents_manage?
  end

  def assign_requirement!(document, key)
    document.requirement_key = JrcRelationship::DocumentRequirements.new(@context).validate_link!(document, key)
  end

  def assign_responsible!(document, id)
    return document.responsible = nil if id.blank?

    candidate_id = Integer(id.to_s, 10)
    return if document.responsible_id == candidate_id

    candidate = @context.assignable_users.find(candidate_id)
    raise ArgumentError, 'Responsible user is not active' unless candidate.active_for_authentication?

    document.responsible = candidate
  end
end
