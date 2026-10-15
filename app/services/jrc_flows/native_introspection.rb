# P9 nativeAdapter domain implementation. This is not an HTTP authentication
# boundary: its caller must authenticate the Broker and supply a current local
# context resolver. Neither request nor browser appContext can supply that trust.
class JrcFlows::NativeIntrospection
  class Denied < StandardError; end

  REQUEST_KEYS = %w[nonce externalActorId accountId destinationRevision inboxIds].freeze
  SCOPES = %w[flow:read flow:edit flow:publish flow:bind].freeze
  MAX_SAFE_INTEGER = 9_007_199_254_740_991
  UUID = Regexp.new(
    '\A(?:[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}|' \
    '00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\z',
    Regexp::IGNORECASE
  )

  # Resolver must read the authenticated installation registration from local
  # server storage on every call, without network I/O or cached Account objects.
  def initialize(context_resolver:)
    @context_resolver = context_resolver
  end

  def call(raw)
    request = validate_request!(raw)
    context = @context_resolver.call
    unless context.is_a?(Hash) && context[:organization_id].is_a?(String) && context[:origin].is_a?(String)
      raise Denied, 'FLOW_HOST_CONTEXT_UNAVAILABLE'
    end
    unless context[:account_id] == request['accountId'] && context[:destination_revision] == request['destinationRevision']
      raise Denied, 'FLOW_CONTEXT_CHANGED'
    end

    actor = request.fetch('externalActorId')
    raise Denied, 'FLOW_ACTOR_UNMAPPED' unless /\A[1-9][0-9]*\z/.match?(actor) && positive_id?(actor.to_i)

    Account.transaction do
      account = Account.lock('FOR SHARE').find_by(id: context.fetch(:account_id))
      decision = request.merge('accountActive' => false, 'member' => false, 'featureEnabled' => false, 'role' => nil)
      next decision unless account

      decision['accountActive'] = account.active? == true
      decision['featureEnabled'] = JrcFlows::Access.enabled?(account) == true
      member = AccountUser.lock('FOR SHARE').find_by(account_id: account.id, user_id: actor.to_i)
      next decision unless member && complete_membership?(account.id, actor.to_i, request.fetch('inboxIds'))

      permissions = member.permissions
      decision['member'] = true
      decision['role'] = if member.custom_role_id.nil? && permissions.include?('administrator') && !permissions.include?('custom_role')
                           'administrator'
                         else
                           'agent'
                         end
      decision
    end
  end

  # Optional host-side action check; the Broker still applies its separate
  # credential/session scope intersection. Never authorize a supplied decision.
  def authorize!(request, scope:)
    raise Denied, 'FLOW_INVALID_SCOPE' unless SCOPES.include?(scope)

    decision = call(request)
    raise Denied, 'FLOW_ACCOUNT_INACTIVE' unless decision['accountActive']
    raise Denied, 'FLOW_FEATURE_DISABLED' unless decision['featureEnabled']
    raise Denied, 'FLOW_MEMBERSHIP_REQUIRED' unless decision['member']
    raise Denied, 'FLOW_CAPABILITY_NOT_GRANTED' if scope != 'flow:read' && decision['role'] != 'administrator'

    decision
  end

  private

  def complete_membership?(account_id, user_id, ids)
    actual = Inbox.where(account_id: account_id, id: ids).pluck(:id)
    assigned = InboxMember.where(user_id: user_id, inbox_id: ids).pluck(:inbox_id)
    actual.sort == ids.sort && assigned.uniq.sort == ids.sort
  end

  def positive_id?(value)
    value.is_a?(Integer) && value.positive? && value <= MAX_SAFE_INTEGER
  end

  def validate_request!(raw)
    valid = raw.is_a?(Hash) && raw.keys.all? { |key| key.is_a?(String) } && raw.keys.sort == REQUEST_KEYS.sort &&
            raw['nonce'].is_a?(String) && UUID.match?(raw['nonce']) &&
            raw['externalActorId'].is_a?(String) && /\A[A-Za-z0-9:_-]{1,80}\z/.match?(raw['externalActorId']) &&
            positive_id?(raw['accountId']) && positive_id?(raw['destinationRevision']) &&
            raw['inboxIds'].is_a?(Array) && raw['inboxIds'].length.between?(1, 100) &&
            raw['inboxIds'].all? { |id| positive_id?(id) } && raw['inboxIds'].uniq.length == raw['inboxIds'].length
    raise Denied, 'FLOW_INVALID_REQUEST' unless valid

    raw.transform_values { |value| value.dup }
  end
end
