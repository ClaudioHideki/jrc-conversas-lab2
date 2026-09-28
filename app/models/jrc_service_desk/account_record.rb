# frozen_string_literal: true

# CP2-only base. The CP1 abstract base and native models remain untouched.
class JrcServiceDesk::AccountRecord < JrcServiceDesk::Base
  self.abstract_class = true

  validate :persisted_account_required
  validate :ownership_is_immutable, on: :update

  protected

  def ownership_columns
    [:account_id]
  end

  def ownership_is_immutable
    ownership_columns.each do |column|
      errors.add(column, 'cannot be changed') if will_save_change_to_attribute?(column)
    end
  end

  def persisted_account_required
    errors.add(:account, 'must exist') unless account&.persisted?
  end

  def validate_account_reference(name)
    reflection = self.class.reflect_on_association(name)
    related = public_send(name)
    return if related.nil? && public_send(reflection.foreign_key).nil? && reflection.options[:optional]

    unless related&.persisted? && related.respond_to?(:account_id) && related.account_id == account_id
      errors.add(name, 'must belong to the same account')
    end
  end

  def validate_active_reference(name)
    reflection = self.class.reflect_on_association(name)
    return unless new_record? || will_save_change_to_attribute?(reflection.foreign_key)

    related = public_send(name)
    errors.add(name, 'must be active') if related && related.respond_to?(:active?) && !related.active?
  end
end
