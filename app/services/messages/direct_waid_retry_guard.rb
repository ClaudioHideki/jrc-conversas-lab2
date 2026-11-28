require 'digest'
require 'uri'

# This guard limits retry only. A WAID never establishes delivery or read state.
class Messages::DirectWaidRetryGuard
  SETTING = 'jrc_direct_waid_retry_guard'.freeze
  DISPLAY = 'jrc_direct_waid_retry_blocked'.freeze

  def self.applies?(message)
    return false unless message.outgoing? && !message.private? && message.sender_type == 'User' && message.sender_id.present?
    return false unless message.source_id.to_s.start_with?('WAID:')

    key = message.source_id.delete_prefix('WAID:')
    return false unless key.size.between?(1,512) && !key.match?(JrcBroker::OutboundReceipt::INVALID_PROVIDER_ID)

    inbox = message.inbox
    inbox&.account_id == message.account_id && configured?(inbox)
  end

  def self.configured?(inbox)
    return false unless inbox&.channel_type == 'Channel::Api'

    channel = inbox.channel
    setting = channel.additional_attributes.to_h[SETTING]
    return false unless setting.is_a?(Hash) && setting['version'] == 1 && setting['account_id'] == inbox.account_id &&
                        setting['inbox_id'] == inbox.id && setting['origin'].present? &&
                        setting['origin'] == ENV['FRONTEND_URL'].to_s.delete_suffix('/')

    url = channel.webhook_url
    return false unless url.present? && !url.match?(/[[:cntrl:]]/) && Digest::SHA256.hexdigest(url) == setting['webhook_url_sha256']

    uri = URI.parse(url)
    uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo && !uri.query && !uri.fragment &&
      uri.path.match?(%r{\A/chatwoot/webhook/(?:[A-Za-z0-9_()-]|%2[89])+\z})
  rescue URI::InvalidURIError
    false
  end
end
