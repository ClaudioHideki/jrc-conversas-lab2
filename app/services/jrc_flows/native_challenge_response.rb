class JrcFlows::NativeChallengeResponse
  def self.parse!(raw, configuration:, challenge_id:, inbox_ids:)
    fail! unless raw.is_a?(Hash) && raw.keys.sort == %w[challengeId context expiresAt registration state] && raw['challengeId'] == challenge_id &&
                 %w[PENDING VERIFYING COMMITTED].include?(raw['state']) && raw['expiresAt'].is_a?(String) && raw['expiresAt'].end_with?('Z')
    fail! unless Time.iso8601(raw['expiresAt']) <= configuration.expires_at
    tuple = raw['context']
    fail! unless tuple.is_a?(Hash) && tuple.keys.sort == %w[accountCredentialVersion accountId credentialId credentialRevision destinationRevision
                                                            targets] &&
                 tuple['credentialId'] == configuration.credential_id && tuple['credentialRevision'] == configuration.credential_revision &&
                 tuple['destinationRevision'] == configuration.destination_revision &&
                 tuple['accountCredentialVersion'] == configuration.account_credential_version &&
                 tuple['accountId'] == configuration.account_id && tuple['targets'].is_a?(Array) && tuple['targets'].any?
    targets = tuple['targets'].map do |target|
      fail! unless target.is_a?(Hash) && target.keys.sort == %w[channelId inboxId integrationId provider transport]
      target.merge('accountId' => configuration.account_id)
    end
    JrcFlows::NativeContextResponse.parse!(
      { 'credential' => { 'id' => tuple['credentialId'], 'revision' => tuple['credentialRevision'],
                          'expiresAt' => configuration.expires_at.iso8601, 'scopes' => ['flow:read'] },
        'destination' => { 'organizationId' => configuration.organization_id, 'origin' => configuration.host_origin,
                           'accountId' => configuration.account_id, 'destinationRevision' => tuple['destinationRevision'],
                           'accountCredentialVersion' => tuple['accountCredentialVersion'] },
        'targets' => targets, 'nextCursor' => nil }, account_id: configuration.account_id, origin: configuration.host_origin
    )
    fail! unless targets.map { |target| target['inboxId'] }.sort == inbox_ids.sort
    if raw['state'] == 'COMMITTED'
      registration = raw['registration']
      fail! unless registration.is_a?(Hash) && registration.keys.sort == %w[expiresAt id revision] &&
                   registration['id'].is_a?(String) && JrcFlows::NativeContextResponse::UUID.match?(registration['id']) &&
                   registration['revision'].is_a?(Integer) && registration['revision'].positive? &&
                   registration['expiresAt'].is_a?(String) && registration['expiresAt'].end_with?('Z') &&
                   Time.iso8601(registration['expiresAt']) <= configuration.expires_at
    else
      fail! unless raw['registration'].nil?
    end
    JSON.parse(JSON.generate(raw))
  rescue ArgumentError, TypeError
    fail!
  end

  def self.fail!
    raise JrcFlows::NativeContextResponse::Invalid, 'FLOW_BROKER_CONTEXT_INVALID'
  end
end
