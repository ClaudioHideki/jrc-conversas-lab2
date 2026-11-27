class JrcCampaigns::MetaStatusReplayJob < ApplicationJob
  queue_as :low

  def perform(event_id, attempt = 0)
    event = JrcCampaigns::StatusEvent.find_by(id: event_id)
    return unless event && event.matched_at.nil?
    return if JrcCampaigns::MetaStatusService.apply(event)

    self.class.set(wait: 1.minute).perform_later(event.id, attempt + 1) if attempt < 5
  end
end
