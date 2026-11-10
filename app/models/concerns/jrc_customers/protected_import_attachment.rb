module JrcCustomers::ProtectedImportAttachment
  extend ActiveSupport::Concern
  included do
    validate :preserve_customer_import_owner
    before_update :preserve_customer_import_file, if: :customer_import_locator_changing?
    before_destroy :preserve_customer_import_file
  end

  private

  def preserve_customer_import_owner
    return unless blob && JrcCustomers::ImportBlob.protected?(blob)
    return if persisted? && !customer_import_locator_changing?

    errors.add(:blob, 'must remain with its original import') unless original_import_attachment?
  end

  def original_import_attachment?
    return false unless new_record? && record_type == 'DataImport' && name == 'import_file'
    return false unless record.customer_master_import? && record.pending?
    return false unless blob.metadata[JrcCustomers::ImportBlob::MARKER] == record_id

    !self.class.exists?(blob_id: blob.id)
  end

  def preserve_customer_import_file
    original = ActiveStorage::Blob.find_by(id: attribute_in_database('blob_id'))
    return unless original && JrcCustomers::ImportBlob.protected?(original)

    raise ActiveRecord::ReadOnlyRecord, 'Import files are immutable'
  end

  def customer_import_locator_changing?
    %w[blob_id record_id record_type name].any? { |field| will_save_change_to_attribute?(field) }
  end
end
