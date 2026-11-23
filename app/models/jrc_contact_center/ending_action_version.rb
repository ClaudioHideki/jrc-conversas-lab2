# frozen_string_literal: true

# Unapplied WIP: immutable materialization of the existing Account ACW policy, not another configuration catalogue.
class JrcContactCenter::EndingActionVersion < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  # Native :private parameter filtering also protects SQL binds for this column.
  alias_attribute :definition, :private_definition
  self.filter_attributes += %i[definition private_definition definition_sha256]

  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :source_audit_id, :definition, presence: true
  validate :valid_definition

  def self.record_change!(account:, definition:, audit:)
    metadata = JrcContactCenter::EndingActions::Catalogue.new(account: account).head
    create!(account: account, revision: definition.fetch('version'), head_nonce: metadata.fetch('nonce'),
            definition: definition, source_audit_id: audit.id).reload
  end

  private

  def valid_definition
    JrcContactCenter::EndingActions::RuleDefinition.new.call(definition)
  end
end
