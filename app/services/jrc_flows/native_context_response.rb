require 'time'

class JrcFlows::NativeContextResponse
  class Invalid < StandardError; end
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  SCOPES = %w[flow:read flow:edit flow:publish flow:bind].freeze

  def self.parse!(raw, account_id:, origin:)
    invalid = -> { raise Invalid, 'FLOW_BROKER_CONTEXT_INVALID' }
    exact = ->(value, keys) { value.is_a?(Hash) && value.keys.sort == keys.sort }
    positive = ->(value) { value.is_a?(Integer) && value.between?(1, 9_007_199_254_740_991) }
    uuid = ->(value) { value.is_a?(String) && UUID.match?(value) }
    invalid.call unless exact.call(raw, %w[credential destination targets nextCursor])
    c, d, targets = raw.values_at('credential', 'destination', 'targets')
    invalid.call unless exact.call(c, %w[id revision expiresAt scopes]) && uuid.call(c['id']) && positive.call(c['revision']) &&
                        c['expiresAt'].is_a?(String) && c['expiresAt'].end_with?('Z') &&
                        c['scopes'].is_a?(Array) && c['scopes'].any? && c['scopes'].uniq == c['scopes'] && (c['scopes'] - SCOPES).empty?
    Time.iso8601(c['expiresAt'])
    invalid.call unless exact.call(d, %w[organizationId origin accountId destinationRevision accountCredentialVersion]) &&
                        uuid.call(d['organizationId']) && d['origin'] == origin && d['accountId'] == account_id &&
                        positive.call(d['destinationRevision']) && positive.call(d['accountCredentialVersion'])
    invalid.call unless targets.is_a?(Array) && targets.length <= 100
    targets.each do |target|
      invalid.call unless exact.call(target, %w[integrationId channelId accountId inboxId transport provider]) &&
                          uuid.call(target['integrationId']) && uuid.call(target['channelId']) &&
                          target['accountId'] == account_id && positive.call(target['inboxId']) &&
                          %w[BROKER_TRANSPORT CENTRAL_TRANSPORT].include?(target['transport']) && [nil, 'BAILEYS'].include?(target['provider'])
    end
    invalid.call unless %w[integrationId inboxId].all? { |key| targets.map { |target| target[key] }.uniq.length == targets.length }
    invalid.call unless raw['nextCursor'].nil? || uuid.call(raw['nextCursor'])
    JSON.parse(JSON.generate(raw))
  rescue ArgumentError, TypeError
    raise Invalid, 'FLOW_BROKER_CONTEXT_INVALID'
  end
end
