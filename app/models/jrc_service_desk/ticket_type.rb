# frozen_string_literal: true

class JrcServiceDesk::TicketType < JrcServiceDesk::NamedUnitRecord
  validate :form_configuration

  private

  def form_configuration
    fields = JrcServiceDesk::CatalogueFields.new(form_fields)
    errors.add(:form_fields, 'must define unique supported fields') unless fields.valid? && !fields.duplicate_keys?
  end
end
