class Pabx::SyncJob < ApplicationJob
  queue_as :low

  def perform(account_id, integration_id = nil)
    scope = TelephonyIntegration.where(account_id: account_id)
    scope = scope.where(id: integration_id) if integration_id
    integration = scope.first
    Pabx::Sync.new(integration).call if integration
  rescue Pabx::Error => error
    retryable = %w[TIMEOUT UNAVAILABLE RATE_LIMITED PROVIDER_ERROR].include?(error.code)
    raise unless retryable && executions < 3

    retry_job(wait: executions * 30.seconds)
  end
end
