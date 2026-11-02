class WebhookJob < ApplicationJob
  queue_as :medium
  self.log_arguments = false

  retry_on JrcBroker::WebhookDelivery::Unavailable, wait: :polynomially_longer, attempts: 8 do |job, error|
    url, payload, webhook_type = job.arguments
    kwargs = job.arguments.last.is_a?(Hash) ? job.arguments.last : {}
    Webhooks::Trigger.new(url, payload, webhook_type, secret: kwargs[:secret], delivery_id: kwargs[:delivery_id]).handle_failure(error)
  end

  #  There are 3 types of webhooks, account, inbox and agent_bot
  def perform(url, payload, webhook_type = :account_webhook, secret: nil, delivery_id: nil, campaign_recovery_token: nil)
    if campaign_recovery_token
      return unless JrcCampaigns::BrokerRecoveryService.callback_allowed?(payload, token: campaign_recovery_token,
                                                                                callback: { url: url, secret: secret, delivery_id: delivery_id })
    end

    options = { secret: secret, delivery_id: delivery_id }
    options[:campaign_recovery_token] = campaign_recovery_token if campaign_recovery_token
    Webhooks::Trigger.execute(url, payload, webhook_type, **options)
  end
end
