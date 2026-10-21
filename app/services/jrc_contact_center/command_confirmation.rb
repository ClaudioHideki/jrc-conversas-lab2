# frozen_string_literal: true

class JrcContactCenter::CommandConfirmation
  def initialize(event_record:)
    @event = event_record
  end

  def call
    body = @event.payload['payload']
    data = (body.is_a?(Hash) ? body : {}).merge(@event.payload.except('payload'))
    command = JrcContactCenter::Command.where(account_id: @event.account_id).find_by!(command_id: data.fetch('command_id'))
    command.with_lock do
      next if %w[confirmed_by_pabx rejected].include?(command.status)

      status = @event.event_type == 'command.confirmed' ? 'confirmed_by_pabx' : 'rejected'
      command.update!(status: status, completed_at: @event.occurred_at,
                      response: { 'provider_status' => status, 'reason_code' => data['reason_code'] })
    end
    command
  end
end
