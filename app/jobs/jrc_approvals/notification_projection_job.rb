class JrcApprovals::NotificationProjectionJob < ApplicationJob
  queue_as :low

  def perform(event_id)
    JrcApprovals::NotificationProjection.new(event_id).call
  end
end
