class JrcRelationship::Record < ApplicationRecord
  self.abstract_class = true
  belongs_to :account
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  belongs_to :owner, class_name: 'User', optional: true
  validate :tenant_references

  private

  def tenant_references
    self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
      next if reflection.name == :account
      value = public_send(reflection.name)
      next unless value
      valid = value.is_a?(User) ? account.users.exists?(value.id) : value.account_id == account_id
      errors.add(reflection.name, 'must belong to this account') unless valid
    end
  end
end
