class JrcBroker::HistorySyncMediaSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless ENV['JRC_HISTORY_SYNC_V2_ENABLED'] == 'true'

    intents = JrcBrokerHistoryMedia.where(state: 'ATTACH_PENDING').where(next_attempt_at: ..Time.current).order(:next_attempt_at, :id).limit(100)
    intents.pluck(:id).each do |id|
      JrcBroker::HistorySyncMediaJob.perform_later(id)
    end
  end
end
