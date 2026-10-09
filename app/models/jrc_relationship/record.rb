class JrcRelationship::Record < ApplicationRecord
  self.abstract_class = true
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment', optional: true
  validates :assignment, presence: true, unless: -> { is_a?(JrcRelationship::Survey) && source_type.present? }
  belongs_to :owner, class_name: 'User', optional: true
  validate :tenant_references

  private

  def tenant_references
    self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
      next if reflection.name == :account

      value = public_send(reflection.name)
      next unless value
      # A dispatched shared survey keeps the historical author after native membership revocation.
      # Creation or any changed reference still requires current membership in this tenant.
      next if historical_survey_author?(reflection)

      valid = value.is_a?(User) ? account.users.exists?(value.id) : value.account_id == account_id
      errors.add(reflection.name, 'must belong to this account') unless valid
    end
  end

  def historical_survey_author?(reflection)
    is_a?(JrcRelationship::Survey) && source_type.present? && persisted? && %i[owner agent].include?(reflection.name) &&
      !will_save_change_to_attribute?(reflection.foreign_key)
  end
end
