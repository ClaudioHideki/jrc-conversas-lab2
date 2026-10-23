class JrcBroker::InboxSyncJob < ApplicationJob
  queue_as :low

  def self.enqueue_for(account)
    return unless JrcBroker::Configuration.enabled? && account&.feature_enabled?('jrc_broker')
    return unless Account.active.exists?(id: account.id) && JrcBrokerIntegration.exists?(account_id: account.id)

    perform_later(account.id)
  end

  def perform(account_id, after_inbox_id = 0)
    account = configured_account(account_id)
    return unless account

    admin = account.administrators.order(:id).first
    return unless admin

    # Coalesce overlapping callbacks/recovery without holding a DB transaction
    # during HTTP. Owner-checked release cannot delete a later worker's lease.
    key = "jrc:broker:inbox-sync:#{account.id}"
    token = SecureRandom.uuid
    return unless Redis::Alfred.set(key, token, nx: true, ex: 300)

    begin
      result = JrcBroker::Context.new(account: account, user: admin).sync_inboxes!(after_inbox_id: after_inbox_id)
    ensure
      Redis::Alfred.delete_if_equals(key, token)
    end
    self.class.perform_later(account.id, result[:next_after]) if result[:next_after]
  rescue JrcBroker::Client::Error, JrcBroker::Configuration::InvalidConfiguration, JrcBroker::CredentialStore::InvalidCredential
    # No credentials, remote payloads, or customer data in logs. The scheduled
    # reconciliation recovers after a temporary outage without replaying actions.
    Rails.logger.warn("JRC Broker inbox registration pending account_id=#{account_id}")
  end

  private

  def configured_account(account_id)
    return unless JrcBroker::Configuration.enabled?

    account = Account.active.find_by(id: account_id)
    account if account&.feature_enabled?('jrc_broker') && JrcBrokerIntegration.exists?(account_id: account.id)
  end
end
