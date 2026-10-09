# frozen_string_literal: true

class JrcServiceDesk::NotificationPolicySelector
  def self.call(record, channel)
    ticket = record.ticket
    scope = JrcServiceDesk::NotificationPolicyVersion.where(account_id: record.account_id, unit_id: record.unit_id,
                                                            event_type: JrcServiceDesk::NotificationEvent.type(record), channel: channel)
    matches = specific_policies(scope, ticket.ticket_type_id, ticket.service_id)
    return nil if matches.size > 1 # Equal specificity needs an explicit combined policy.

    matches.first || latest(scope, nil, nil) # A specific OFF policy blocks the general ON policy.
  end

  def self.specific_policies(scope, type_id, service_id)
    exact = latest(scope, type_id, service_id) if type_id || service_id
    return [exact] if exact
    return [] unless type_id && service_id

    [[nil, service_id], [type_id, nil]].filter_map { |type, service| latest(scope, type, service) }
  end

  def self.latest(scope, type_id, service_id)
    scope.where(ticket_type_id: type_id, service_id: service_id).order(version: :desc).first
  end

  private_class_method :specific_policies, :latest
end
