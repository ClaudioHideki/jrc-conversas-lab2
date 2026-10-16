class Pabx::ScheduleJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    TelephonyIntegration.where("pabx_settings @> ?", { enabled: true, sync_enabled: true }.to_json).find_each do |integration|
      enqueue(integration)
    end
  end

  def enqueue(integration)
    integration.with_lock do
      settings = Pabx::Settings.new(integration)
      return false unless settings.sync_enabled?

      last = integration.pabx_sync_state.values_at('queued_at', 'last_attempt_at').compact.max
      return false if last && Time.iso8601(last) > settings.value('interval_seconds', 300).seconds.ago

      integration.update!(pabx_sync_state: integration.pabx_sync_state.merge('queued_at' => Time.current.iso8601))
      Pabx::SyncJob.perform_later(integration.account_id, integration.id)
      true
    end
  end
end
