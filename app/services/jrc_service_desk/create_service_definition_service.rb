# frozen_string_literal: true

# Existing entry point retained; delegates to the same authorized/audited catalogue command.
class JrcServiceDesk::CreateServiceDefinitionService < JrcServiceDesk::BaseService
  def call(unit_id:, attributes:, idempotency_key: nil)
    JrcServiceDesk::ConfigurationService.new(user_context: @native_context).create(
      resource: 'services', unit_id: unit_id, attributes: attributes,
      idempotency_key: idempotency_key || SecureRandom.uuid).record
  end
end
