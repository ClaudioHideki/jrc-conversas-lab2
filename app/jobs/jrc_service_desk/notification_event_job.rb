class JrcServiceDesk::NotificationEventJob < ApplicationJob
  queue_as :high

  def perform(event_id)
    event = JrcServiceDesk::TicketEvent.find(event_id)
    JrcServiceDesk::NotificationEngine.new(event).call if JrcServiceDesk::NotificationEvent.active?(event)
  end
end
