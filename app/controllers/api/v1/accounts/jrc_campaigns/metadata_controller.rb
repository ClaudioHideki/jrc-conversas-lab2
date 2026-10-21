class Api::V1::Accounts::JrcCampaigns::MetadataController < Api::V1::Accounts::JrcCampaigns::BaseController
  def show
    whatsapp = whatsapp_inboxes
    render json: {
      account_name: Current.account.name,
      contacts_count: Current.account.contacts.where.not(phone_number: [nil, '']).count,
      email_contacts_count: Current.account.contacts.where.not(email: [nil, '']).count,
      source_inboxes: source_inboxes,
      labels: Current.account.labels.order(:title).map { |label| { id: label.id, title: label.title, color: label.color } },
      inboxes: whatsapp,
      whatsapp_inboxes: whatsapp,
      email_inboxes: email_inboxes,
      pipelines: pipelines,
      sanitized_lists: Current.account.jrc_campaign_sanitized_lists.order(created_at: :desc).map { |list| sanitized_list_json(list) },
      blacklist_count: Current.account.jrc_campaign_blacklists.count
    }
  end

  private

  def source_inboxes
    Current.account.inboxes.order(:name).map do |inbox|
      { id: inbox.id, name: inbox.name, channel_type: inbox.channel_type }
    end
  end

  def whatsapp_inboxes
    Current.account.inboxes.includes(:channel).filter_map do |inbox|
      connector = JrcCampaigns::EvolutionConnector.for(inbox)
      if connector
        next({ id: inbox.id, name: inbox.name, phone_number: connector.sender_number, provider: 'Evolution Demo',
               connector: 'evolution', health_status: 'UNKNOWN', health_error: false, templates: [],
               min_interval_seconds: connector.min_interval_seconds, daily_limit: connector.daily_limit })
      end
      next unless inbox.channel_type == 'Channel::Whatsapp'

      channel = inbox.channel
      {
        id: inbox.id,
        name: inbox.name,
        phone_number: channel.phone_number,
        provider: channel.provider,
        health_status: channel.phone_number_health.to_h['status'],
        health_error: channel.phone_number_health_error.present?,
        health_checked_at: channel.phone_number_health_checked_at,
        templates: Array(channel.message_templates).select { |template| template['status'].to_s.casecmp('approved').zero? }
      }
    end
  end

  def email_inboxes
    Current.account.inboxes.includes(:channel).filter_map do |inbox|
      next unless inbox.channel_type == 'Channel::Email'

      channel = inbox.channel
      oauth_ready = channel.imap_enabled? && (channel.google? || channel.microsoft?)
      global_smtp_ready = ENV.fetch('SMTP_ADDRESS', nil).present? || Rails.env.development?
      connected = (channel.smtp_enabled? || oauth_ready || global_smtp_ready) && !channel.reauthorization_required?
      {
        id: inbox.id,
        name: inbox.name,
        email_address: channel.email,
        provider: channel.provider.presence || (channel.smtp_enabled? ? 'SMTP' : 'E-mail'),
        health_status: connected ? 'CONNECTED' : 'DISCONNECTED',
        health_error: !connected,
        templates: []
      }
    end
  end

  def pipelines
    Current.account.jrc_crm_pipelines.includes(:stages).order(:position).map do |pipeline|
      {
        id: pipeline.id,
        name: pipeline.name,
        stages: pipeline.stages.select(&:active?).map { |stage| { id: stage.id, name: stage.name, color: stage.color, position: stage.position } }
      }
    end
  end

  def sanitized_list_json(list)
    { id: list.id, name: list.name, stats: list.stats, created_at: list.created_at }
  end
end
