class JrcFlows::OwnershipEffects
  class Duplicate < StandardError; end

  class Completion
    def initialize(token, kind, message_id)
      @token = token
      @kind = kind
      @message_id = message_id
    end

    def trigger_transactional_callbacks? = true
    def self.run_commit_callbacks_on_first_saved_instances_in_transaction = false
    def _new_record_before_last_commit = false
    def _new_record_before_last_commit=(_value); end
    def destroyed? = false
    def before_committed!(*); end
    def committed!(**) = JrcFlows::OwnershipEffects.complete!(@token, @kind, @message_id, true)
    def rolledback!(**) = JrcFlows::OwnershipEffects.complete!(@token, @kind, @message_id, false)
  end

  def self.perform(reference:, kind:)
    context=Thread.current[:jrc_flow_ownership]
    return yield unless context

    JrcFlows::OwnershipGuard.checkpoint!
    token=SecureRandom.uuid
    invoked=false
    JrcFlows::OwnershipLedger.transaction_sql do |db|
      exists=db.select_value(JrcFlows::OwnershipLedger.sql(
                               'SELECT EXISTS(SELECT 1 FROM jrc_flow_ownership_effects ' \
                               'WHERE scope_key=? AND generation=? AND effect_reference=?)',
                               context[:scope_key], context[:generation], reference.to_s
                             ))
      raise Duplicate, 'FLOW_EFFECT_RECONCILIATION_REQUIRED' if exists

      db.execute(JrcFlows::OwnershipLedger.sql(
                   'INSERT INTO jrc_flow_ownership_effects(id,scope_key,generation,execution_id,effect_reference,kind,state,' \
                   "created_at,updated_at) VALUES(?,?,?,?,?,?,'DISPATCHED',clock_timestamp(),clock_timestamp())",
                   token, context[:scope_key], context[:generation], context[:execution_id], reference.to_s, kind
                 ))
    end
    begin
      JrcFlows::OwnershipGuard.checkpoint!
      invoked=true
      result=yield
      JrcFlows::OwnershipGuard.checkpoint!
      message_id=kind=='MESSAGE' && result.is_a?(Message) ? result.id : nil
      JrcFlows::OwnershipLedger.transaction_sql do |db|
        db.execute(JrcFlows::OwnershipLedger.sql(
                     "UPDATE jrc_flow_ownership_effects SET state='OBSERVED',message_id=?,updated_at=clock_timestamp() WHERE id=?", message_id, token
                   ))
      end
      observer=Completion.new(token, kind, message_id)
      if ApplicationRecord.connection.transaction_open?
        ApplicationRecord.connection.current_transaction.add_record(observer)
      else
        context[:pending] << [token, kind, message_id]
      end
      result
    rescue Exception
      JrcFlows::OwnershipLedger.transaction_sql do |db|
        db.execute(JrcFlows::OwnershipLedger.sql('UPDATE jrc_flow_ownership_effects SET state=?,updated_at=clock_timestamp() WHERE id=?',
                                                 invoked ? 'UNKNOWN' : 'CANCELED', token))
      end
      raise
    end
  end

  def self.complete!(token, kind, message_id, committed)
    state=if !committed
            kind=='EXTERNAL' ? 'UNKNOWN' : 'CANCELED'
          elsif kind=='MESSAGE'
            message_id ? 'QUEUED' : 'UNKNOWN'
          else
            'CONFIRMED'
          end
    JrcFlows::OwnershipLedger.transaction_sql do |db|
      db.execute(JrcFlows::OwnershipLedger.sql(
                   'UPDATE jrc_flow_ownership_effects SET state=?,updated_at=clock_timestamp() ' \
                   "WHERE id=? AND state IN('DISPATCHED','OBSERVED')", state, token
                 ))
    end
    refresh_message!(message_id) if committed && message_id
  end

  def self.finish_pending!(committed)
    context=Thread.current[:jrc_flow_ownership]
    return unless context

    pending=context[:pending]
    context[:pending]=[]
    pending.each { |token, kind, message_id| complete!(token, kind, message_id, committed) }
  end

  def self.refresh_message!(message_id)
    message=Message.find_by(id: message_id)
    return unless message

    # Message starts as sent in the host schema. Only a delivery/read receipt
    # establishes transport completion for an independently queued intention.
    state=if %w[delivered read].include?(message.status)
            'CONFIRMED'
          elsif message.content_attributes.to_h['jrc_flow_delivery']=='cancelled' ||
                message.content_attributes.to_h['jrc_native_delivery']=='cancelled'
            'CANCELED'
          end
    return unless state

    JrcFlows::OwnershipLedger.transaction_sql do |db|
      db.execute(JrcFlows::OwnershipLedger.sql(
                   'UPDATE jrc_flow_ownership_effects SET state=?,updated_at=clock_timestamp() ' \
                   "WHERE message_id=? AND kind='MESSAGE' AND state='QUEUED'", state, message_id
                 ))
    end
  end
end
