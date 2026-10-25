# frozen_string_literal: true

class JrcServiceDesk::RetryClockAlertService < JrcServiceDesk::BaseService
  def call(unit_id:, alert_id:, expected_attempts:, reason:)
    raise ArgumentError unless reason.is_a?(String) && reason.strip.length.between?(1, 2000)

    with_unit(unit_id) do |unit|
      raise Pundit::NotAuthorizedError unless context.capability?(:queues_manage) && context.capability?(:sla_view)

      row = JrcServiceDesk::ClockAlertDelivery.where(account_id: context.account.id, unit_id: unit.id).lock.find(JrcServiceDesk::Input.id(alert_id))
      authorize!(row.ticket, :update?)
      raise JrcServiceDesk::IdempotencyConflict unless expected_attempts == row.attempts && %w[blocked failed].include?(row.state) && row.attempts < 3
      raise ArgumentError if JrcServiceDesk::ClockAlerts.blocker(row)

      append_event!(row.ticket, 'resource_updated', 'clock_alert_retry_id' => row.id, 'reason' => reason.strip, 'attempts' => row.attempts)
      row.update!(state: 'queued', reason: nil)
      row
    end
  end
end
