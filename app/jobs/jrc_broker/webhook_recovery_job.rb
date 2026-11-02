class JrcBroker::WebhookRecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JrcBrokerWebhookObligation.where("(state = 'pending' AND available_at <= ?) OR (state = 'running' AND lease_until <= ?)",
                                     Time.current, Time.current).order(:id).limit(100).pluck(:id).each do |id|
      JrcBroker::WebhookObligationJob.perform_later(id)
    end
  end
end
