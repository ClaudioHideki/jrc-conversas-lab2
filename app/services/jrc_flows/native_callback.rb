require 'digest'
require 'active_support/security_utils'

class JrcFlows::NativeCallback
  class Denied < StandardError; end

  def initialize(resolve_current: nil, authority_factory: nil)
    @resolve_current = resolve_current || ->(digest) { JrcFlowNativeRegistration.current.find_by(callback_digest: digest) }
    @authority_factory = authority_factory || ->(context) { JrcFlows::NativeIntrospection.new(context_resolver: -> { context }) }
  end

  def call(authorization:, request:)
    match = /\ABearer ([A-Za-z0-9_-]{43})\z/.match(authorization.to_s)
    deny! unless match
    digest = Digest::SHA256.hexdigest(match[1])
    record = @resolve_current.call(digest)
    deny! unless record && ActiveSupport::SecurityUtils.secure_compare(record.callback_digest.to_s, digest)
    targets = record.tuple.is_a?(Hash) ? record.tuple['targets'] : nil
    deny! unless targets.is_a?(Array) && targets.length.between?(1, 100) && targets.all? do |target|
      target.is_a?(Hash) && target['inboxId'].is_a?(Integer)
    end
    deny! unless request.is_a?(Hash) && request['inboxIds'].is_a?(Array) && request['inboxIds'].any? &&
                 (request['inboxIds'] - targets.map { |target| target['inboxId'] }).empty?
    snapshot = identity(record)
    result = @authority_factory.call(account_id: record.account_id, organization_id: record.organization_id,
                                     origin: record.host_origin, destination_revision: record.destination_revision).call(request)
    current = @resolve_current.call(digest)
    deny! unless current && identity(current) == snapshot
    result
  end

  private

  def identity(record)
    [record.account_id, record.organization_id, record.host_origin, record.destination_revision, record.revision, record.callback_digest,
     JSON.generate(record.tuple)]
  end

  def deny!
    raise Denied, 'FLOW_NATIVE_CALLBACK_DENIED'
  end
end
