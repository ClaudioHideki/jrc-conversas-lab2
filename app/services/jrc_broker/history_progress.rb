class JrcBroker::HistoryProgress
  COUNTS = %w[chats capturedMessages persistedMessages duplicateMessages projectedMessages
              pendingMedia verifiedMedia unavailableMedia blockedRecords].freeze
  RUN_FIELDS = %w[schemaVersion id organizationId channelId instanceId revision state capture
                  persistence projection sourceTotalKnown lastError counts].freeze
  OUTER_FIELDS = %w[schemaVersion organizationId channelId integrationId accountId inboxId destinationRevision run].freeze
  PHASES = {
    'state' => %w[RUNNING PAUSED CANCELED COMPLETED PARTIAL BLOCKED],
    'capture' => %w[WAITING_IDENTITY CAPTURING COMPLETE PARTIAL BLOCKED],
    'persistence' => %w[PENDING RUNNING COMPLETE BLOCKED],
    'projection' => %w[NOT_CONFIGURED PENDING RUNNING COMPLETE BLOCKED]
  }.freeze

  def self.present!(value, binding:, integration:)
    valid = value.is_a?(Hash) && value['schemaVersion'] == 2 &&
            value.values_at('organizationId', 'integrationId', 'accountId', 'inboxId', 'destinationRevision') ==
            [integration.organization_id, binding.integration_id, binding.account_id, binding.inbox_id, integration.destination_revision] &&
            JrcBroker::Client::UUID.match?(value['channelId'].to_s) && value.key?('run')
    invalid! unless valid
    result = value.slice(*OUTER_FIELDS)
    result['run'] = run!(value['run'], value, binding) unless value['run'].nil?
    result
  end

  def self.run!(run, envelope, binding)
    invalid! unless run.is_a?(Hash) && identity_valid?(run, envelope, binding) && state_valid?(run) && counts_valid?(run['counts'])
    invalid! if run['state'] == 'COMPLETED' && !complete?(run)

    run.slice(*RUN_FIELDS).merge('counts' => run['counts'].slice(*COUNTS))
  end

  def self.identity_valid?(run, envelope, binding)
    run['schemaVersion'] == 2 && JrcBroker::Client::UUID.match?(run['id'].to_s) &&
      run.values_at('organizationId', 'channelId', 'instanceId') == [envelope['organizationId'], envelope['channelId'], binding.instance_id]
  end

  def self.state_valid?(run)
    integer?(run['revision']) && run['revision'].positive? && [true, false].include?(run['sourceTotalKnown']) &&
      PHASES.all? { |key, states| states.include?(run[key]) } && safe_error?(run['lastError'])
  end

  def self.safe_error?(value)
    value.nil? || /\A[A-Z][A-Z0-9_]{0,127}\z/.match?(value.to_s)
  end

  def self.counts_valid?(counts)
    counts.is_a?(Hash) && COUNTS.all? { |key| integer?(counts[key]) } &&
      counts['persistedMessages'] + counts['duplicateMessages'] <= counts['capturedMessages'] &&
      counts['projectedMessages'] <= counts['persistedMessages']
  end

  def self.complete?(run)
    counts = run['counts']
    phases_complete?(run) &&
      counts['persistedMessages'] + counts['duplicateMessages'] == counts['capturedMessages'] &&
      (run['projection'] != 'COMPLETE' || counts['projectedMessages'] == counts['persistedMessages']) &&
      counts.values_at('pendingMedia', 'unavailableMedia', 'blockedRecords').all?(&:zero?)
  end

  def self.phases_complete?(run)
    run['capture'] == 'COMPLETE' && run['persistence'] == 'COMPLETE' && %w[COMPLETE NOT_CONFIGURED].include?(run['projection'])
  end

  def self.integer?(value)
    value.is_a?(Integer) && value.between?(0, 9_007_199_254_740_991)
  end

  def self.invalid!
    raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
  end
  private_class_method :run!, :identity_valid?, :state_valid?, :safe_error?, :counts_valid?, :complete?, :phases_complete?, :integer?, :invalid!
end
