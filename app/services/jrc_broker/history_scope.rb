# Shared authority for callback-free history receivers. Call only inside a transaction.
class JrcBroker::HistoryScope
  Result = Struct.new(:account, :inbox, :integration, :binding, keyword_init: true)

  def initialize(authority)
    @authority = authority
  end

  def call(inbox_id, organization_id, integration_id)
    @authority.authorize!(lock: true)
    account = @authority.account
    raise ActiveRecord::RecordNotFound unless JrcBroker::Configuration.enabled? && account.feature_enabled?('jrc_broker')
    raise ArgumentError, 'identity' unless [organization_id, integration_id].all? { |value| JrcBroker::HistoryImport::UUID.match?(value.to_s) }

    registered_scope(account, inbox_id, organization_id, integration_id)
  end

  private

  def registered_scope(account, inbox_id, organization_id, integration_id)
    integration = JrcBrokerIntegration.lock('FOR SHARE').find_by!(account_id: account.id)
    binding = JrcBrokerInboxBinding.lock('FOR SHARE').find_by!(account_id: account.id, inbox_id: Integer(inbox_id))
    raise ArgumentError, 'scope' unless integration.organization_id == organization_id && binding.integration_id == integration_id

    inbox = account.inboxes.lock('FOR SHARE').where(channel_type: 'Channel::Api').find(binding.inbox_id)
    Result.new(account: account, inbox: inbox, integration: integration, binding: binding).freeze
  end
end
