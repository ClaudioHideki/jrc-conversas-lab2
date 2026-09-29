module JrcOperations
  # Every persisted relation is checked again at the model boundary, including imports.
  module AccountScopedRecord
    extend ActiveSupport::Concern
    included { validate :jrc_validate_account_references }

    private

    def jrc_validate_account_references
      return unless respond_to?(:account_id) && account_id && respond_to?(:account) && account
      self.class.reflect_on_all_associations(:belongs_to).each do |reflection|
        next if reflection.polymorphic? || reflection.name == :account
        related = public_send(reflection.name)
        next unless related
        valid = if related.is_a?(::User)
                  account.users.exists?(id: related.id)
                elsif related.respond_to?(:account_id)
                  related.account_id == account_id
                else
                  true
                end
        errors.add(reflection.name, 'nao pertence a esta conta') unless valid
      end
    end
  end
end
