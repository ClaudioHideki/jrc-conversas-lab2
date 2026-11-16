class JrcBroker::LiveIngressMediaSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    pending = JrcBrokerLiveReceipt.where(state: 'MEDIA_PENDING').where(next_attempt_at: ..Time.current).order(:next_attempt_at, :id).limit(100)
    pending.pluck(:id).each { |id| JrcBroker::LiveIngressMediaJob.perform_later(id) }
  end
end
