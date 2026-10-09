# frozen_string_literal: true

class JrcServiceDesk::Category < JrcServiceDesk::NamedUnitRecord
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error
  belongs_to :parent, class_name: 'JrcServiceDesk::Category', optional: true, inverse_of: :subcategories
  has_many :subcategories, class_name: 'JrcServiceDesk::Category', foreign_key: :parent_id, dependent: :restrict_with_error, inverse_of: :parent
  validate :classification_integrity

  private

  def classification_integrity
    validate_unit_reference(:parent)
    validate_active_reference(:parent)
    errors.add(:parent, 'must be a different root category') if parent && (parent.id == id || parent.parent_id)
    fields = JrcServiceDesk::CatalogueFields.new(form_fields)
    errors.add(:form_fields, 'must define unique supported fields') unless fields.valid? && !fields.duplicate_keys?
  end
end
