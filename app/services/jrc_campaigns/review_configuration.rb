require 'digest'

# Remote evidence is fetched before locks; only this in-memory value crosses into the write transaction.
class JrcCampaigns::ReviewConfiguration
  Prepared = Data.define(:campaign_id, :account_id, :created_by_id, :configuration, :local_state)
  FIELDS = %w[delivery_channel name inbox_id trigger_type scheduled_at audience_type audience_config message_body rotation_mode delay_min_seconds
              delay_max_seconds sending_window conversation_mode recurrence_config follow_up_config].freeze

  def initialize(campaign)
    @campaign = campaign
  end

  def prepare
    campaign.reload
    local_state = current
    configuration = remote_configuration(local_state.fetch('configuration').deep_dup)
    Prepared.new(campaign.id, campaign.account_id, campaign.created_by_id, configuration, local_state)
  end

  def matches?(prepared)
    prepared.is_a?(Prepared) && [prepared.campaign_id, prepared.account_id, prepared.created_by_id] ==
      [campaign.id, campaign.account_id, campaign.created_by_id] && prepared.local_state == current
  end

  def local_configuration
    result = campaign.as_json(only: FIELDS).merge(
      'steps' => campaign.steps.order(:position, :id).map { |step| step.as_json.except('created_at', 'updated_at') },
      'inboxes' => campaign.campaign_inboxes.order(:position, :id).map { |link| link.as_json.except('created_at', 'updated_at') }
    )
    result.merge(connector_configuration)
  end

  # Called only inside the short Campaign lock. Freeze the existing source rows until the write commits.
  def lock_sources!(actor: nil)
    campaign.account.lock!('FOR SHARE')
    links = lock_campaign_sources!(actor)
    JrcBrokerIntegration.where(account_id: campaign.account_id).order(:id).lock('FOR SHARE').load
    lock_sender_sources!((links.map(&:inbox_id) + [campaign.inbox_id]).compact)
    campaign.association(:inbox).reset
    campaign.association(:account).reset
  end

  private

  attr_reader :campaign

  def remote_configuration(configuration)
    brokers = campaign.broker_connectors
    return configuration if brokers.empty?

    configuration['broker_connectors'] = brokers.map do |connector|
      local = configuration.fetch('broker_connectors').find { |row| row['inbox_id'] == connector.inbox.id }
      local.merge('identity_revision' => connector.transport(campaign.created_by, release_connection: true).fetch('identityRevision'))
    end
    configuration
  end

  def connector_configuration
    { 'evolution_connectors' => campaign.evolution_connectors, 'broker_connectors' => campaign.broker_connectors }.filter_map do |key, connectors|
      [key, connectors.map(&:public_configuration)] if connectors.any?
    end.to_h
  end

  def lock_campaign_sources!(actor)
    AccountUser.where(account_id: campaign.account_id, user_id: [campaign.created_by_id, actor&.id].compact).order(:id).lock('FOR SHARE').load
    campaign.steps.order(:id).lock('FOR SHARE').load
    campaign.campaign_inboxes.order(:id).lock('FOR SHARE').to_a
  end

  def lock_sender_sources!(inbox_ids)
    inboxes = Inbox.where(account_id: campaign.account_id, id: inbox_ids).order(:id).lock('FOR SHARE').to_a
    inboxes.each { |inbox| inbox.channel.lock!('FOR SHARE') }
    JrcBrokerInboxBinding.where(account_id: campaign.account_id, inbox_id: inboxes.map(&:id)).order(:id).lock('FOR SHARE').load
  end

  def current
    {
      'configuration' => local_configuration,
      'approval_revision' => campaign.attributes.slice('review_digest', 'approved_digest', 'approved_by_id', 'approved_at', 'approval_expires_at'),
      'broker_enabled' => JrcBroker::Configuration.enabled? && campaign.account.feature_enabled?('jrc_broker'),
      'broker_sources' => campaign.broker_connectors.map do |connector|
        channel = connector.inbox.channel
        { 'inbox_id' => connector.inbox.id, 'channel_id' => channel.id, 'callback' => channel.webhook_url,
          'channel_revision' => channel.updated_at.iso8601(6),
          'credential_revision' => Digest::SHA256.hexdigest(connector.integration.encrypted_control_key.to_s) }
      end
    }
  end
end
