# frozen_string_literal: true

class JrcServiceDesk::PublishNotificationPolicyService < JrcServiceDesk::BaseService
  FIELDS = %w[event_type channel enabled inbox_id template template_version confirmed expected_version ticket_type_id service_id].freeze

  def call(unit_id:, attributes:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    validate_confirmation!(values)
    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:notifications_manage)

      { 'ticket_type_id' => JrcServiceDesk::TicketType, 'service_id' => JrcServiceDesk::Service }.each do |name, model|
        next unless values.key?(name)

        scope = model.where(account_id: context.account.id, unit_id: unit.id)
        scope = scope.where(active: true) if values['enabled']
        values[name] = values[name].nil? ? nil : scope.find(JrcServiceDesk::Input.id(values[name])).id
      end
      publish(unit, values, native_inbox(values))
    end
  end

  private

  def validate_confirmation!(values)
    valid = values['confirmed'] == true && [true, false].include?(values['enabled'])
    raise ArgumentError, 'Explicit confirmation and enabled state required' unless valid
  end

  def native_inbox(values)
    inbox = values['inbox_id'] && context.account.inboxes.find(JrcServiceDesk::Input.id(values['inbox_id']))
    JrcServiceDesk::NativeExecutionContext.with(context.to_h) { authorize!(inbox, :show?) } if inbox
    valid = inbox && JrcServiceDesk::NotificationEngine.channel(inbox) == values['channel']
    raise ArgumentError, 'Configured native channel required' if values['enabled'] && !valid

    inbox
  end

  def publish(unit, values, inbox)
    event_type = values.fetch('event_type', 'customer_interaction')
    fields = values.except('confirmed', 'inbox_id', 'expected_version').merge('event_type' => event_type, 'inbox_id' => inbox&.id)
    versions = JrcServiceDesk::NotificationPolicyVersion.where(account: context.account, unit: unit,
                                                               event_type: event_type, channel: values.fetch('channel'),
                                                               ticket_type_id: values['ticket_type_id'], service_id: values['service_id'])
    current = versions.maximum(:version).to_i
    if values.key?('expected_version') && current != JrcServiceDesk::Input.version(values['expected_version'])
      raise JrcServiceDesk::IdempotencyConflict
    end

    JrcServiceDesk::NotificationPolicyVersion.create!(fields.merge(account: context.account, unit: unit,
                                                                   published_by_membership: actor_membership, version: current + 1,
                                                                   digest: JrcServiceDesk::CanonicalJson.digest(fields)))
  end
end
