class JrcBroker::InboxSyncSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless JrcBroker::Configuration.enabled?

    JrcBrokerIntegration.includes(:account).find_each do |integration|
      JrcBroker::InboxSyncJob.enqueue_for(integration.account)
    end
  end
end
