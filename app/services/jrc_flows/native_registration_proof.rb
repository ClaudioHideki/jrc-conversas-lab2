require 'digest'

class JrcFlows::NativeRegistrationProof
  class Denied < StandardError; end
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
  KEYS = %w[challengeId nonce credentialId credentialRevision destinationRevision accountCredentialVersion accountId targets].freeze
  TARGET_KEYS = %w[integrationId channelId inboxId transport provider].freeze

  def initialize(resolve_pending: nil, authority_factory: nil, sql_clock: nil)
    @sql_clock = sql_clock || -> { ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time }
    @resolve_pending = resolve_pending || lambda do |digest|
      JrcFlowNativeRegistration.where(callback_digest: digest, state: %w[PENDING CHALLENGE_VERIFIED])
                               .where('expires_at > clock_timestamp()').first
    end
    @authority_factory = authority_factory || ->(context) { JrcFlows::NativeIntrospection.new(context_resolver: -> { context }) }
  end

  def call(bearer:, request:)
    deny! unless bearer.is_a?(String) && /\A[A-Za-z0-9_-]{43}\z/.match?(bearer)
    validate!(request)
    request = JSON.parse(JSON.generate(request))
    digest = Digest::SHA256.hexdigest(bearer)
    record = @resolve_pending.call(digest)
    deny! unless record && record.callback_digest.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(record.callback_digest, digest)

    record.with_lock do
      deny! unless %w[PENDING CHALLENGE_VERIFIED].include?(record.state) && record.expires_at > @sql_clock.call
      deny! unless record.challenge_id == request['challengeId'] && record.account_id == request['accountId'] &&
                   record.tuple == request.except('challengeId', 'nonce')
      deny! if record.confirmation_nonce && record.confirmation_nonce != request['nonce']

      context = { organization_id: record.organization_id, origin: record.host_origin,
                  account_id: record.account_id, destination_revision: record.destination_revision }
      native_request = { 'nonce' => request['nonce'], 'externalActorId' => record.created_by_id.to_s, 'accountId' => record.account_id,
                         'destinationRevision' => record.destination_revision, 'inboxIds' => request['targets'].map { |target| target['inboxId'] } }
      @authority_factory.call(context).authorize!(native_request, scope: 'flow:bind')
      deny! unless record.expires_at > @sql_clock.call
      # One nonce slot per challenge. Exact repeats only observe that same slot.
      record.update!(confirmation_nonce: request['nonce'], state: 'CHALLENGE_VERIFIED') unless record.confirmation_nonce
      request.merge('authorized' => true)
    end
  rescue Denied
    raise
  rescue StandardError
    deny!
  end

  private

  def deny!
    raise Denied, 'FLOW_REGISTRATION_HOST_AUTHORITY_DENIED'
  end

  def positive?(value)
    value.is_a?(Integer) && value.positive? && value <= 9_007_199_254_740_991
  end

  def exact_keys?(value, keys)
    value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) } && value.keys.sort == keys.sort
  end

  def validate!(request)
    deny! unless exact_keys?(request, KEYS)
    deny! unless %w[challengeId nonce credentialId].all? { |key| request[key].is_a?(String) && UUID.match?(request[key]) }
    deny! unless %w[credentialRevision destinationRevision accountCredentialVersion accountId].all? { |key| positive?(request[key]) }
    targets = request['targets']
    deny! unless targets.is_a?(Array) && targets.length.between?(1, 100)
    targets.each do |target|
      deny! unless exact_keys?(target, TARGET_KEYS) && %w[integrationId channelId].all? do |key|
        target[key].is_a?(String) && UUID.match?(target[key])
      end &&
                   positive?(target['inboxId']) && %w[BROKER_TRANSPORT CENTRAL_TRANSPORT].include?(target['transport']) &&
                   [nil, 'BAILEYS'].include?(target['provider'])
    end
    deny! unless targets.map { |target| target['integrationId'] }.uniq.length == targets.length && targets.map do |target|
      target['inboxId']
    end.uniq.length == targets.length
  end
end
