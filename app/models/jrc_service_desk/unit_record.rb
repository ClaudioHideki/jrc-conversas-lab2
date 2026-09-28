# frozen_string_literal: true

class JrcServiceDesk::UnitRecord < JrcServiceDesk::AccountRecord
  self.abstract_class = true

  belongs_to :unit, class_name: 'JrcServiceDesk::Unit', optional: false
  validate :unit_account_is_consistent

  protected

  def ownership_columns
    super + [:unit_id]
  end

  def unit_account_is_consistent
    validate_account_reference(:unit)
  end

  def validate_unit_reference(name)
    validate_account_reference(name)
    related = public_send(name)
    return unless related

    errors.add(name, 'must belong to the same unit') unless related.respond_to?(:unit_id) && related.unit_id == unit_id
  end
end
