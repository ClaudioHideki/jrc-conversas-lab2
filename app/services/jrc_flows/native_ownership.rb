class JrcFlows::NativeOwnership
  class Denied < StandardError; end
  class NotDrained < StandardError; end
  KEYS=%w[organizationId origin accountId inboxId destinationRevision accountCredentialVersion integrationId cutoverId cutoverRevision
          expectedOwnerRevision originCapabilityRevision expectedAgentBotId expectedAgentBotCallback expectedHostSourceSha
          expectedHostImageDigest nonce externalActorId brokerActorId leaseToken leaseExpiresAt].freeze
  def initialize(identity: nil, broker_proof: nil)
    @identity=identity || ->(request) { JrcFlows::OwnershipIdentity.verify!(request) }
    @broker_proof=broker_proof || ->(record, request) { JrcFlows::NativeOwnershipBrokerProof.observe!(record, request) }
  end

  def authorize!(registration, request, reopen: false)
    unless request.is_a?(Hash) && (request.keys-KEYS-(reopen ? ['expectedCurrentOwnerRevision'] : [])).empty? && (KEYS-request.keys).empty?
      raise Denied
    end

    registration.reload
    now=ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    unless registration.state=='ACTIVE' && registration.revoked_at.nil? && registration.expires_at>now && registration.credential_expires_at>now
      raise Denied
    end
    unless request['organizationId']==registration.organization_id && request['origin']==registration.host_origin &&
           request['origin']==JrcFlows::OwnershipGuard.local_origin && request['accountId']==registration.account_id &&
           request['destinationRevision']==registration.destination_revision &&
           request['accountCredentialVersion']==registration.account_credential_version
      raise Denied
    end
    unless request['brokerActorId'].nil? && request['externalActorId'].is_a?(String) && /\A[1-9][0-9]*\z/.match?(request['externalActorId'])
      raise Denied
    end

    %w[inboxId cutoverRevision originCapabilityRevision].each { |key| raise Denied unless request[key].is_a?(Integer) && request[key].positive? }
    pair=[request['expectedAgentBotId'], request['expectedAgentBotCallback']]
    raise Denied unless pair==[nil, nil] || (pair[0].is_a?(Integer) && pair[0].positive? && pair[1].is_a?(String) && pair[1].present?)
    raise Denied unless request['expectedOwnerRevision'].is_a?(Integer) && request['expectedOwnerRevision']>=0

    %w[integrationId cutoverId nonce leaseToken].each do |key|
      raise Denied unless request[key].is_a?(String) && JrcFlows::NativeClient::UUID.match?(request[key])
    end
    lease=Time.iso8601(request.fetch('leaseExpiresAt'))
    raise Denied unless lease>now && lease<=now+60
    unless /\A[a-f0-9]{40}\z/.match?(request['expectedHostSourceSha'].to_s) &&
           /\Asha256:[a-f0-9]{64}\z/.match?(request['expectedHostImageDigest'].to_s)
      raise Denied
    end

    target=registration.tuple.fetch('targets').find do |t|
      t['integrationId']==request['integrationId'] && t['inboxId']==request['inboxId']
    end
    raise Denied unless target
    raise Denied unless registration.bindings.exists?(inbox_id: request['inboxId'], integration_id: request['integrationId'],
                                                      channel_id: target['channelId'], registration_revision: registration.revision)

    [registration.created_by_id, request['externalActorId'].to_i].uniq.each do |actor|
      authority=JrcFlows::NativeHostAuthority.new(account_id: registration.account_id, user_id: actor)
      authority.administrator!

      authority.authorize!(record: registration, inbox_ids: [request['inboxId']], scopes: ['flow:bind'], nonce: request['nonce'])
    end
    target
  rescue ArgumentError, KeyError, JrcFlows::NativeClient::Error, JrcFlows::NativeIntrospection::Denied
    raise Denied, 'FLOW_OWNERSHIP_AUTHORITY_CHANGED'
  end

  def scope!(registration, request)
    key=JrcFlows::OwnershipGuard.key(registration.host_origin, registration.account_id, request['inboxId'])
    JrcFlowOwnershipScope.create_or_find_by!(scope_key: key) do |s|
      s.host_origin=registration.host_origin
      s.account_id=registration.account_id
      s.inbox_id=request['inboxId']
    end
  end

  def match!(epoch, registration, request)
    unless epoch && epoch.registration_id==registration.id && epoch.registration_revision==registration.revision &&
           epoch.organization_id==registration.organization_id && epoch.integration_id==request['integrationId'] &&
           epoch.cutover_revision==request['cutoverRevision'] && epoch.expected_owner_revision==request['expectedOwnerRevision'] &&
           epoch.broker_agent_bot_id==request['expectedAgentBotId'] && epoch.broker_agent_bot_callback==request['expectedAgentBotCallback']
      raise Denied
    end
  end

  def fence!(registration:, request:)
    target=authorize!(registration, request)
    identity=@identity.call(request)
    scope=scope!(registration, request)
    scope.with_lock do
      authorize!(registration, request)
      verify_bot!(request)
      epoch=scope.epochs.find_by(cutover_id: request['cutoverId'], cutover_revision: request['cutoverRevision'])
      if epoch
        match!(epoch, registration, request)
        raise Denied unless %w[FENCED DRAINED].include?(epoch.state) && scope.current_epoch_id==epoch.id
      else
        raise Denied unless scope.state=='LEGACY'

        epoch=scope.epochs.create!(
          registration: registration, organization_id: registration.organization_id, integration_id: request['integrationId'],
          channel_id: target['channelId'], cutover_id: request['cutoverId'], cutover_revision: request['cutoverRevision'],
          registration_revision: registration.revision, generation: scope.generation, expected_owner_revision: request['expectedOwnerRevision'],
          broker_agent_bot_id: request['expectedAgentBotId'], broker_agent_bot_callback: request['expectedAgentBotCallback'],
          state: 'FENCED', lease_token: request['leaseToken'], lease_until: request['leaseExpiresAt'], accepted_at: Time.current
        )
        scope.update!(state: 'FENCED', current_epoch_id: epoch.id)
      end
    end
    # Closure commits before touching runner rows; never scope→runner deadlock
    # against a runner checkpoint using its independent ledger connection.
    quiesce!(scope)
    JrcFlows::OwnershipQueues.cancel!(scope)
    proof!(scope, registration, request, identity)
  end

  def observe!(registration:, request:)
    authorize!(registration, request)
    scope=scope!(registration, request)
    proof!(scope, registration, request, @identity.call(request))
  end

  def proof!(scope, registration, request, identity)
    scope.with_lock do
      authorize!(registration, request)
      verify_bot!(request)

      epoch=scope.epochs.find_by(cutover_id: request['cutoverId'], cutover_revision: request['cutoverRevision'])
      match!(epoch, registration, request)
      raise Denied unless scope.state=='FENCED' && scope.current_epoch_id==epoch.id && %w[FENCED DRAINED].include?(epoch.state)

      work=counts(scope)
      raise NotDrained, 'FLOW_OWNERSHIP_NOT_DRAINED' unless work.values.all?(&:zero?)

      epoch.update!(state: 'DRAINED', lease_token: request['leaseToken'], lease_until: request['leaseExpiresAt'])
      { 'organizationId' => registration.organization_id, 'accountId'=>scope.account_id, 'inboxId'=>scope.inbox_id,
        'integrationId'=>epoch.integration_id, 'cutoverId' => epoch.cutover_id, 'cutoverRevision'=>epoch.cutover_revision,
        'expectedOwnerRevision'=>epoch.expected_owner_revision, 'hostFenceRevision'=>epoch.cutover_revision, 'admissionClosed'=>true,
        'liveRuns'=>work[:runs], 'legacyJobs'=>work[:jobs], 'uncertainEffects'=>work[:effects], 'guardedPaths'=>identity.fetch(:paths),
        'hostSourceSha'=>identity.fetch(:source), 'hostImageDigest'=>identity.fetch(:image) }
    end
  end

  def verify_bot!(request)
    JrcFlows::NativeResponders.installed!
    inbox=Inbox.find_by!(id: request['inboxId'], account_id: request['accountId'])
    JrcFlows::NativeResponders.verify_pair!(inbox, request['expectedAgentBotId'], request['expectedAgentBotCallback'])
  rescue JrcFlows::OwnershipGuard::Closed, ActiveRecord::RecordNotFound
    raise Denied, 'FLOW_NATIVE_POLICY_NOT_INSTALLED'
  end

  def remote_connections(scope)
    JrcFlowConnection.where(base_url: scope.host_origin, remote_account_id: scope.account_id)
  end

  def quiesce!(scope)
    active=JrcFlowOwnershipExecution.where(scope_key: scope.scope_key, authority_kind: 'LEGACY',
                                           state: 'RUNNING').where('expires_at>clock_timestamp()').exists?
    local=JrcFlowRun.joins(:conversation).where(account_id: scope.account_id, conversations: { inbox_id: scope.inbox_id })
    unless active
      local.where(status: 'running').pluck(:id).each { |id| retain_legacy_unknown!(scope, "legacy-run:#{id}") }
      JrcFlowRemoteSession.where(connection_id: remote_connections(scope).select(:id), inbox_id: scope.inbox_id,
                                 status: 'running').pluck(:id).each do |id|
        retain_legacy_unknown!(scope, "legacy-remote-session:#{id}")
      end
    end
    local.where(status: %w[running waiting delayed]).update_all(status: 'paused', error: 'Executor legacy fechado pelo cutover.',
                                                             finished_at: Time.current,
                                                                wake_at: nil)
    JrcFlowRemoteSession.where(connection_id: remote_connections(scope).select(:id), inbox_id: scope.inbox_id,
                              status: %w[ready running waiting delayed]).update_all(
      status: 'paused', error: 'Executor legacy fechado pelo cutover.', finished_at: Time.current, wake_at: nil
    )
    JrcFlowRemoteEvent.where(connection_id: remote_connections(scope).select(:id), status: 'queued').find_each do |event|
      next unless JrcFlows::OwnershipQueues.remote_matches?(scope, event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event))

      event.update!(status: 'failed', error: 'Executor fechado antes do despacho.')
    end
    JrcFlows::OwnershipPlaybook.cancel_queued!(scope)
    JrcFlows::NativeResponders.quiesce_messages!(scope)
    Message.joins(:conversation).where(account_id: scope.account_id, conversations: { inbox_id: scope.inbox_id },
                                       private: false).find_each do |message|
      next unless message.content_attributes.to_h['jrc_flow_run_id'].present? && message.content_attributes.to_h['jrc_flow_delivery']=='queued'

      message.update!(status: :failed, content_attributes: message.content_attributes.to_h.merge('jrc_flow_delivery'=>'cancelled'))
      JrcFlows::OwnershipEffects.refresh_message!(message.id)
    end
  end

  def retain_legacy_unknown!(scope, reference)
    JrcFlows::OwnershipLedger.transaction_sql do |db|
      db.execute(JrcFlows::OwnershipLedger.sql(
                   "INSERT INTO jrc_flow_ownership_effects(id,scope_key,generation,execution_id,effect_reference,kind,state," \
                   "created_at,updated_at) VALUES(?,?,?,?,?,'EXTERNAL','UNKNOWN',clock_timestamp(),clock_timestamp()) " \
                   'ON CONFLICT(scope_key,generation,effect_reference) DO NOTHING',
                   SecureRandom.uuid, scope.scope_key, scope.generation, SecureRandom.uuid, reference
                 ))
    end
  end

  def counts(scope)
    JrcFlowOwnershipExecution.where(scope_key: scope.scope_key, authority_kind: 'LEGACY',
                                    state: 'RUNNING').where('expires_at<=clock_timestamp()').update_all(state: 'UNKNOWN')
    scoped_messages=Message.joins(:conversation).where(account_id: scope.account_id, conversations: { inbox_id: scope.inbox_id })
    scoped_messages.find_each do |message|
      JrcFlows::OwnershipEffects.refresh_message!(message.id) if message.content_attributes.to_h['jrc_flow_run_id'].present?
    end
    local_runs=JrcFlowRun.joins(:conversation).where(account_id: scope.account_id, conversations: { inbox_id: scope.inbox_id },
                                                     status: %w[running waiting delayed]).count
    remote_runs=JrcFlowRemoteSession.where(connection_id: remote_connections(scope).select(:id), inbox_id: scope.inbox_id,
                                           status: %w[ready running waiting delayed]).count
    remote_events=JrcFlowRemoteEvent.where(connection_id: remote_connections(scope).select(:id), status: %w[queued running]).count do |event|
      JrcFlows::OwnershipQueues.remote_matches?(scope, event.connection, JrcFlows::OwnershipEntrypoints.event_inbox(event))
    end
    pending_messages=scoped_messages.where(private: false).count do |message|
      attributes=message.content_attributes.to_h
      attributes['jrc_flow_run_id'].present? && attributes['jrc_flow_delivery']!='cancelled' && !%w[delivered read].include?(message.status)
    end
    playbook = JrcFlows::OwnershipPlaybook.counts(scope)
    { runs: local_runs+remote_runs+JrcFlows::NativeResponders.drain_executions(scope).where(state: 'RUNNING').count,
      jobs: remote_events+JrcFlows::OwnershipQueues.count(scope)+playbook[:jobs],
      effects: pending_messages+JrcFlows::NativeResponders.drain_executions(scope).where(state: 'UNKNOWN').count+
        JrcFlowOwnershipEffect.where(scope_key: scope.scope_key, state: %w[DISPATCHED OBSERVED QUEUED UNKNOWN]).where(
          'NOT EXISTS(SELECT 1 FROM jrc_flow_ownership_executions e WHERE e.id=jrc_flow_ownership_effects.execution_id ' \
          "AND e.authority_kind='BROKER_CALLBACK' AND e.entrypoint='agent-bot-webhook')"
        ).count+playbook[:effects] }
  end

  def retire!(registration:, request:)
    target=authorize!(registration, request)
    scope=scope!(registration, request)
    scope.with_lock do
      authorize!(registration, request)
      epoch=scope.epochs.find_by(cutover_id: request['cutoverId'], cutover_revision: request['cutoverRevision'])
      if epoch
        match!(epoch, registration, request)
        raise Denied unless epoch.state=='NOT_STARTED_RETIRED'
      else
        epoch=scope.epochs.create!(
          registration: registration, organization_id: registration.organization_id, integration_id: request['integrationId'],
          channel_id: target['channelId'], cutover_id: request['cutoverId'], cutover_revision: request['cutoverRevision'],
          registration_revision: registration.revision, generation: scope.generation, expected_owner_revision: request['expectedOwnerRevision'],
          broker_agent_bot_id: request['expectedAgentBotId'], broker_agent_bot_callback: request['expectedAgentBotCallback'],
          state: 'NOT_STARTED_RETIRED', lease_token: request['leaseToken'], lease_until: request['leaseExpiresAt'], retired_at: Time.current
        )
      end
      { 'outcome' => 'NOT_STARTED_RETIRED', 'organizationId'=>registration.organization_id, 'cutoverId'=>epoch.cutover_id,
        'cutoverRevision' => epoch.cutover_revision, 'accountId'=>scope.account_id, 'inboxId'=>scope.inbox_id, 'integrationId'=>epoch.integration_id }
    end
  end

  def reopen!(registration:, request:)
    authorize!(registration, request, reopen: true)
    scope=scope!(registration, request)
    identity=@identity.call(request)
    raise Denied unless request['expectedCurrentOwnerRevision'].is_a?(Integer) && request['expectedCurrentOwnerRevision']>=0

    observed=@broker_proof.call(registration, request)
    now=ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
    expected={ 'organizationId' => registration.organization_id, 'cutoverId'=>request['cutoverId'], 'cutoverRevision'=>request['cutoverRevision'],
               'integrationId' => request['integrationId'], 'accountId'=>scope.account_id, 'inboxId'=>scope.inbox_id, 'nonce'=>request['nonce'],
               'ownerRevision'=>request['expectedCurrentOwnerRevision'], 'brokerDrained'=>true }
    raise Denied unless observed.is_a?(Hash) && expected.all? do |key, value|
      observed[key]==value
    end && Time.iso8601(observed.fetch('proofValidUntil'))>now && Time.iso8601(observed.fetch('proofValidUntil'))<=now+10

    scope.with_lock do
      authorize!(registration, request, reopen: true)
      verify_bot!(request)

      epoch=scope.epochs.find_by(cutover_id: request['cutoverId'], cutover_revision: request['cutoverRevision'])
      match!(epoch, registration, request)
      raise Denied unless scope.state=='FENCED' && scope.current_epoch_id==epoch.id && %w[FENCED
                                                                                          DRAINED].include?(epoch.state) &&
                            Time.iso8601(observed.fetch('proofValidUntil'))>
                            ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time
      raise NotDrained unless counts(scope).values.all?(&:zero?)

      epoch.update!(state: 'REOPENED', reopened_owner_revision: request['expectedCurrentOwnerRevision'], reopened_at: Time.current)
      scope.update!(state: 'LEGACY', generation: scope.generation+1, current_epoch_id: nil)
      { 'reopened' => true, 'generation'=>scope.generation, 'cutoverId'=>epoch.cutover_id, 'hostSourceSha'=>identity.fetch(:source),
        'hostImageDigest' => identity.fetch(:image) }
    end
  rescue JrcFlows::NativeClient::Error, KeyError, ArgumentError
    raise Denied, 'FLOW_BROKER_DRAIN_PROOF_REQUIRED'
  end
end
