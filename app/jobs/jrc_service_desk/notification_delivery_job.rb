# frozen_string_literal: true

class JrcServiceDesk::NotificationDeliveryJob < ApplicationJob
  queue_as :high

  def perform(delivery_id)
    row = JrcServiceDesk::NotificationDelivery.find(delivery_id)
    row.with_lock do
      next unless row.state == 'queued' && row.message_id.nil?

      blocker = JrcServiceDesk::NotificationEngine.blocker(row)
      if blocker
        row.update!(state: 'blocked', reason: blocker)
        next
      end
      message = build_message(row)
      row.update!(message: message, payload_digest: JrcServiceDesk::NotificationExecution.payload_digest(message, row))
    end
  end

  private

  def build_message(row)
    member = row.execution_membership.account_user
    # A system notification does not take over the native conversation handoff.
    JrcServiceDesk::NativeExecutionContext.with(user: member.user, account: row.account, account_user: member) do
      Messages::MessageBuilder.new(nil, row.conversation, message_parameters(row)).perform
    end
  end

  def message_parameters(row)
    fields = row.source_snapshot.presence || JrcServiceDesk::NotificationSource.new(row.ticket_note || row.ticket_event).fields
    params = { content: JrcServiceDesk::NotificationSource.render(row.notification_policy_version.template, fields),
               message_type: 'outgoing', private: false,
               content_attributes: { service_desk_delivery_id: row.id, service_desk_ticket_id: row.ticket_id } }
    params[:to_emails] = row.recipient if row.channel == 'email'
    params
  end
end
