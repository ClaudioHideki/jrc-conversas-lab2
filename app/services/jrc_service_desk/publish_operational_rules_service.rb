# frozen_string_literal: true

class JrcServiceDesk::PublishOperationalRulesService < JrcServiceDesk::BaseService
  def call(unit_id:, kind:, definition:, enabled:, expected_version:)
    raise ArgumentError, 'Explicit enabled boolean required' unless [true, false].include?(enabled)

    definition = JrcServiceDesk::CanonicalJson.normalize(definition)
    JrcServiceDesk::OperationalRuleContract.validate!(kind, definition)
    with_unit(unit_id) do |unit|
      JrcServiceDesk::OperationalRuleAccess.require!(context, kind, unit)
      current = JrcServiceDesk::OperationalRuleVersion.current(account_id: context.account.id, unit_id: unit.id, kind: kind)
      unless (current&.version || 0) == JrcServiceDesk::Input.version(expected_version)
        raise JrcServiceDesk::IdempotencyConflict, 'Operational configuration changed'
      end

      # Disable remains possible after a target is revoked; it grants no execution.
      JrcServiceDesk::OperationalRuleReferences.new(context: context, unit: unit).validate!(kind, definition) if enabled
      row = JrcServiceDesk::OperationalRuleVersion.new(account: context.account, unit: unit, kind: kind,
                                                       definition: definition, enabled: enabled,
                                                       version: (current&.version || 0) + 1, published_by_membership: actor_membership)
      row.digest = row.expected_digest
      authorize!(row, :create?)
      row.save!
      row
    end
  end
end
