# frozen_string_literal: true

require 'time'

# Records explicitly supplied historical conditions. Does not fetch/verify an external
# provider, calculate a deadline, choose a calendar or mark a milestone as fulfilled.
class JrcServiceDesk::RecordSlaSnapshotService < JrcServiceDesk::BaseService
  FIELDS = (JrcServiceDesk::SlaSnapshot::SOURCE_FIELDS + JrcServiceDesk::SlaSnapshot::JSON_FIELDS +
            %w[calendar_scope timezone captured_at]).freeze

  def call(ticket_id:, attributes:)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    raise ArgumentError, 'All snapshot conditions and provenance are required' unless (FIELDS - values.keys).empty?

    (JrcServiceDesk::SlaSnapshot::SOURCE_FIELDS + %w[calendar_scope timezone]).each do |field|
      values[field] = text(values[field])
    end
    JrcServiceDesk::SlaSnapshot::JSON_FIELDS.each do |field|
      raise ArgumentError, 'Snapshot conditions must be JSON objects' unless values[field].is_a?(Hash)

      values[field] = JrcServiceDesk::CanonicalJson.normalize(values[field])
      JrcServiceDesk::CanonicalJson.dump(values[field])
    end
    values['captured_at'] = explicit_time(values['captured_at'])
    with_ticket(ticket_id, :show?) do |ticket|
      snapshot = JrcServiceDesk::SlaSnapshot.new(values.merge('account' => context.account, 'unit' => ticket.unit,
                                                                 'ticket' => ticket, 'applied_at' => Time.current))
      authorize!(snapshot, :create?)
      JrcServiceDesk::SlaSnapshotWriter.call(snapshot: snapshot, actor: actor_membership)
    end
  end

  private

  def explicit_time(value)
    return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
    unless value.is_a?(String) && value.match?(/(?:Z|[+-][0-9]{2}:[0-9]{2})\z/)
      raise ArgumentError, 'captured_at requires an explicit timezone offset'
    end

    Time.iso8601(value)
  rescue ArgumentError
    raise ArgumentError, 'Invalid captured_at timestamp'
  end
end
