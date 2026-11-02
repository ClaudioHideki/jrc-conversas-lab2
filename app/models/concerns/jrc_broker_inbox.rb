module JrcBrokerInbox
  extend ActiveSupport::Concern

  included do
    has_one :jrc_broker_inbox_binding, dependent: :destroy
    after_create_commit :schedule_broker_registration
  end

  def jrc_broker_bound?
    JrcBroker::Configuration.enabled? && account.feature_enabled?('jrc_broker') && jrc_broker_inbox_binding.present?
  end

  private

  def schedule_broker_registration
    JrcBroker::InboxSyncJob.enqueue_for(account) if channel_type == 'Channel::Api'
  end
end
