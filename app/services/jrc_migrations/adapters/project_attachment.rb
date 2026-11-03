class JrcMigrations::Adapters::ProjectAttachment < JrcMigrations::Adapters::Base
  Prepared = Struct.new(:parent, :payload, :created_at, keyword_init: true)
  private_constant :Prepared

  def model
    ActiveStorage::Attachment
  end

  def scope
    model.where(name: 'attachments', record_type: parent_model.polymorphic_name,
                record_id: parent_model.where(account_id: account.id).select(:id))
  end

  def update_allowed?
    false
  end

  def candidates(_data)
    # A filename or identical bytes alone cannot identify an original attachment.
    []
  end

  def build(data, target: nil)
    parent = resolve_parent!(data)
    payload = JrcMigrations::AttachmentPayload.new(data)
    created = timestamp!(data['created_at'])
    raise JrcMigrations::Error, 'INVALID_SOURCE_DATES' if timestamp!(data['updated_at']) < created
    raise JrcMigrations::Error, 'SOURCE_CREATED_AT_CONFLICT' if target && target.created_at != created
    raise JrcMigrations::Error, 'RELATION_CONFLICT' if target && target.record != parent

    Prepared.new(parent: parent, payload: payload, created_at: created)
  end

  def write!(prepared)
    JrcMigrations::AttachmentStorage.new(account: account, source: @source, prepared: prepared, item: @migration_item).call
  end

  def reserve_media!(item, prepared)
    JrcMigrations::MediaPlan.reserve!(item: item, prepared: prepared)
  end

  def rollback_write!(record)
    JrcMigrations::AttachmentStorage.cleanup!(record.blob)
  end

  def digest(record)
    blob = record.blob
    data = { 'attachment' => record.attributes, 'blob' => blob.attributes.slice('key', 'filename', 'content_type', 'byte_size', 'checksum'),
             'physical_sha256' => JrcMigrations::AttachmentStorage.sha256(blob) }
    JrcMigrations::Catalog.digest(data)
  end

  private

  def parent_model
    JrcProjects::Project
  end

  def parent_field
    'project_id'
  end

  def parent_legacy_field
    'project_legacy_id'
  end

  def parent_domain
    'projects'
  end

  def resolve_parent!(data)
    validate_reference_values!(data.slice(parent_field))
    id = data[parent_field]
    if data[parent_legacy_field].present?
      mapped_id = relation_id!(data[parent_legacy_field], domain: parent_domain)
      raise JrcMigrations::Error, 'RELATION_CONFLICT' if id.present? && id.to_i != mapped_id

      id = mapped_id
    end
    parent = parent_model.find_by(account_id: account.id, id: id)
    raise JrcMigrations::Error, 'RELATION_OUTSIDE_ACCOUNT' unless parent
    raise JrcMigrations::Error, 'INVALID_DESTINATION' unless parent.valid?

    parent
  end
end
