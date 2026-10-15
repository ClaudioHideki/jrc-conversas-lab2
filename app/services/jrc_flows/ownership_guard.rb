require 'digest'
require 'uri'
require 'securerandom'

class JrcFlows::OwnershipGuard
  class Closed < StandardError; end
  PATHS = {
    'listener' => 'app/listeners/jrc_flows_listener.rb', 'dispatch'=>'app/jobs/jrc_flows/dispatch_job.rb',
    'resume' => 'app/jobs/jrc_flows/resume_job.rb', 'recovery'=>'app/jobs/jrc_flows/recovery_job.rb',
    'workflow-turn' => 'app/jobs/jrc_flows/workflow_turn_job.rb', 'runner'=>'app/services/jrc_flows/runner.rb',
    'workflow-runner' => 'app/services/jrc_flows/workflow_runner.rb', 'remote-event'=>'app/jobs/jrc_flows/remote_event_job.rb',
    'remote-resume' => 'app/jobs/jrc_flows/remote_resume_job.rb', 'remote-recovery'=>'app/jobs/jrc_flows/remote_recovery_job.rb',
    'remote-runner' => 'app/services/jrc_flows/remote_runner.rb',
    'playbook-webhook' => 'app/services/jrc_relationship/playbook_flow_webhook_delivery.rb',
    'playbook-resume' => 'app/jobs/jrc_relationship/playbook_flow_resume_job.rb',
    'automation-rule' => 'app/services/automation_rules/action_service.rb',
    'native-reply' => 'app/jobs/send_reply_job.rb',
    'agent-bot-listener' => 'app/listeners/agent_bot_listener.rb',
    'agent-bot-webhook' => 'app/jobs/agent_bots/webhook_job.rb',
    'api-bot-actor' => 'config/initializers/jrc_flow_native_responders.rb',
    'native-policy-config' => 'db/functions/20261015160000_native_responder_config_fence.sql'
  }.freeze

  def self.origin(value)
    value=value.to_s.delete_suffix('/')
    uri=URI.parse(value)
    unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.empty?
      raise Closed,
            'FLOW_OWNERSHIP_ORIGIN_INVALID'
    end

    value
  rescue URI::InvalidURIError
    raise Closed, 'FLOW_OWNERSHIP_ORIGIN_INVALID'
  end

  def self.key(origin_value, account_id, inbox_id)
    raise Closed, 'FLOW_OWNERSHIP_SCOPE_INVALID' unless account_id.to_i.positive? && inbox_id.to_i.positive?

    Digest::SHA256.hexdigest(JSON.generate([origin(origin_value), account_id.to_i, inbox_id.to_i]))
  end

  def self.local_origin = origin(ENV.fetch('FRONTEND_URL'))

  def self.allowed_scope?(origin_value, account_id, inbox_id)
    scope_key=key(origin_value, account_id, inbox_id)
    JrcFlows::OwnershipLedger.connection_pool.with_connection do |db|
      row=db.select_one(JrcFlows::OwnershipLedger.sql('SELECT state FROM jrc_flow_ownership_scopes WHERE scope_key=?', scope_key))
      row.nil? || row['state']=='LEGACY'
    end
  rescue StandardError
    false
  end

  def self.allowed_local?(account_id, inbox_id) = allowed_scope?(local_origin, account_id, inbox_id)

  def self.remote_inboxes(connection, inbox_id = nil)
    values=Array(connection.inbox_ids).map(&:to_i).select(&:positive?).uniq
    return [] if inbox_id && !values.include?(inbox_id.to_i)

    inbox_id ? [inbox_id.to_i] : values
  end

  def self.allowed_remote?(connection, inbox_id = nil)
    values=remote_inboxes(connection, inbox_id)
    values.any? && values.all? { |id| allowed_scope?(connection.base_url, connection.remote_account_id, id) }
  end

  def self.with_local(account_id, inbox_id, path:, reference:, broker_bot: nil, &)
    with_scope(local_origin, account_id, inbox_id, path: path, reference: reference, broker_bot: broker_bot, &)
  end

  def self.with_remote(connection, inbox_id = nil, path:, reference:, &block)
    inboxes=remote_inboxes(connection, inbox_id)
    raise Closed, 'FLOW_OWNERSHIP_SCOPE_REQUIRED' if inboxes.empty?

    work=block
    inboxes.reverse_each do |iid|
      previous=work
      work = -> { with_scope(connection.base_url, connection.remote_account_id, iid, path: path, reference: reference, &previous) }
    end
    work.call
  end

  def self.with_scope(origin_value, account_id, inbox_id, path:, reference:, broker_bot: nil)
    scope_key=key(origin_value, account_id, inbox_id)
    previous=Thread.current[:jrc_flow_ownership]
    if previous && previous[:scope_key]==scope_key
      raise Closed, 'FLOW_OWNERSHIP_AUTHORITY_CHANGED' unless previous[:broker_bot_id] == broker_bot&.id

      checkpoint!
      return yield
    end
    token=SecureRandom.uuid
    generation=nil
    broker_epoch=nil
    JrcFlows::OwnershipLedger.transaction_sql do |db|
      db.execute(JrcFlows::OwnershipLedger.sql(
                   'INSERT INTO jrc_flow_ownership_scopes(scope_key,host_origin,account_id,inbox_id,generation,state,' \
                   "created_at,updated_at) VALUES(?,?,?,?,1,'LEGACY',clock_timestamp(),clock_timestamp()) " \
                   'ON CONFLICT(scope_key) DO NOTHING', scope_key, origin(origin_value), account_id, inbox_id
                 ))
      scope=db.select_one(JrcFlows::OwnershipLedger.sql('SELECT * FROM jrc_flow_ownership_scopes WHERE scope_key=? FOR UPDATE', scope_key))
      if broker_bot
        raise Closed, 'FLOW_OWNERSHIP_FENCED' unless scope

        broker_epoch=JrcFlows::NativeResponders.broker_epoch!(JrcFlowOwnershipScope.instantiate(scope), broker_bot)
      else
        raise Closed, 'FLOW_OWNERSHIP_FENCED' unless scope && scope['state']=='LEGACY'
      end
      generation=scope['generation'].to_i
      db.execute(JrcFlows::OwnershipLedger.sql(
                   "UPDATE jrc_flow_ownership_executions SET state='UNKNOWN',updated_at=clock_timestamp() " \
                   "WHERE scope_key=? AND generation=? AND state='RUNNING' AND expires_at<=clock_timestamp()", scope_key, generation
                 ))
      busy=db.select_value(JrcFlows::OwnershipLedger.sql(
                             'SELECT EXISTS(SELECT 1 FROM jrc_flow_ownership_executions ' \
                             "WHERE scope_key=? AND generation=? AND run_reference=? AND state IN('RUNNING','UNKNOWN'))",
                             scope_key, generation, reference.to_s
                           ))
      raise Closed, 'FLOW_OWNERSHIP_RECONCILIATION_REQUIRED' if busy

      db.execute(JrcFlows::OwnershipLedger.sql(
                   'INSERT INTO jrc_flow_ownership_executions(id,scope_key,generation,entrypoint,run_reference,state,expires_at,' \
                   'created_at,updated_at,authority_kind,authority_bot_id,authority_epoch_id) ' \
                   "VALUES(?,?,?,?,?,'RUNNING',clock_timestamp()+interval '30 seconds',clock_timestamp(),clock_timestamp(),?,?,?)",
                   token, scope_key, generation, path.to_s, reference.to_s,
                   broker_bot ? 'BROKER_CALLBACK' : 'LEGACY', broker_bot&.id, broker_epoch&.id
                 ))
    end
    Thread.current[:jrc_flow_ownership]=
      { scope_key: scope_key, generation: generation, execution_id: token, reference: reference.to_s, pending: [], broker_bot_id: broker_bot&.id,
        broker_epoch_id: broker_epoch&.id }
    begin
      result=yield
      checkpoint!
      JrcFlows::OwnershipEffects.finish_pending!(true)
      result
    rescue Exception
      JrcFlows::OwnershipEffects.finish_pending!(false)
      raise
    ensure
      JrcFlows::OwnershipLedger.transaction_sql do |db|
        db.execute(JrcFlows::OwnershipLedger.sql(
                     "UPDATE jrc_flow_ownership_executions SET state='QUIESCENT',updated_at=clock_timestamp() WHERE id=? AND state='RUNNING'", token
                   ))
      end
      Thread.current[:jrc_flow_ownership]=previous
    end
  end

  def self.checkpoint!
    context=Thread.current[:jrc_flow_ownership]
    return true unless context

    JrcFlows::OwnershipLedger.transaction_sql do |db|
      row=db.select_one(JrcFlows::OwnershipLedger.sql('SELECT * FROM jrc_flow_ownership_scopes WHERE scope_key=? FOR SHARE', context[:scope_key]))
      raise Closed, 'FLOW_OWNERSHIP_FENCED' unless row && row['generation'].to_i==context[:generation]

      if context[:broker_bot_id]
        bot=AgentBot.find_by(id: context[:broker_bot_id])
        raise Closed unless bot

        epoch=JrcFlows::NativeResponders.broker_epoch!(JrcFlowOwnershipScope.instantiate(row), bot)
        raise Closed unless epoch.id==context[:broker_epoch_id]
      else
        raise Closed, 'FLOW_OWNERSHIP_FENCED' unless row['state']=='LEGACY'
      end
      updated=db.update(JrcFlows::OwnershipLedger.sql(
                          "UPDATE jrc_flow_ownership_executions SET expires_at=clock_timestamp()+interval '30 seconds'," \
                          "updated_at=clock_timestamp() WHERE id=? AND state='RUNNING' AND expires_at>clock_timestamp()",
                          context[:execution_id]
                        ))
      raise Closed, 'FLOW_OWNERSHIP_LEASE_CHANGED' unless updated==1
    end
    true
  end
end
