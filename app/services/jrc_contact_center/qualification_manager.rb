# frozen_string_literal: true

class JrcContactCenter::QualificationManager
  def initialize(account:, member:)
    @account = account
    @member = account.account_users.find(member.id)
  end

  def self.ensure_voice!(session)
    return unless session.account.feature_enabled?('jrc_contact_center')

    session.legs.where.not(account_user_id: nil).where.not(answered_at: nil).includes(:account_user).find_each do |leg|
      next unless %w[ended failed].include?(session.status) || %w[ended failed transferred].include?(leg.status)

      new(account: session.account, member: leg.account_user).start!(call_session: session, started_at: leg.ended_at || session.ended_at)
    end
  end

  def start!(call_session: nil, conversation: nil, started_at: nil)
    raise JrcContactCenter::OperationError, 'contact_center_disabled' unless @account.feature_enabled?('jrc_contact_center')
    @account.with_lock do
      target = call_session || conversation
      raise ActiveRecord::RecordNotFound unless target&.account_id == @account.id
      target = target.class.where(account_id: @account.id).lock.find(target.id)
      call_session ? call_session = target : conversation = target

      if call_session
        leg = call_session.legs.where(account_user: @member).where.not(answered_at: nil).order(:id).last
        unless leg && (%w[ended failed].include?(call_session.status) || %w[ended failed transferred].include?(leg.status))
          raise JrcContactCenter::OperationError.new('call_not_ended', status: :conflict)
        end
      elsif !(conversation.inbox.whatsapp? || conversation.inbox.twilio_whatsapp?) || conversation.assignee_id != @member.user_id
        raise JrcContactCenter::OperationError.new('attendance_not_owned', status: :forbidden)
      end
      identity = { account: @account, account_user: @member, call_session: call_session, conversation: conversation,
                   conversation_cycle: conversation ? conversation.additional_attributes.fetch('jrc_acw_cycle', 0).to_i : 0 }
      existing = JrcContactCenter::Qualification.find_by(identity)
      return existing if existing
      raise JrcContactCenter::OperationError.new('conversation_already_resolved', status: :conflict) if conversation&.resolved?

      channel = conversation ? 'whatsapp' : 'voice'
      record = JrcContactCenter::Qualification.create!(identity.merge(channel: channel, started_at: started_at || Time.current,
                                                                      acw_limit_seconds: JrcContactCenter::AcwPolicy.new(account: @account).call[:limits].fetch(channel)))
      state_manager.record_provider_event(state: 'acw', occurred_at: record.started_at, external_event_id: "qualification:#{record.id}:pending",
                                          provider: 'jrc_conversas', derived: true, queue_id: call_session&.current_queue_id,
                                          metadata: { 'qualification_id' => record.id, 'jrc_call_session_id' => call_session&.id })
      record
    end
  end

  def complete!(record, attributes)
    @account.with_lock do
      record = JrcContactCenter::Qualification.where(account: @account, account_user: @member).lock.find(record.id)
      return record if record.completed_at

      if record.conversation
        record.conversation.lock!
        unless record.conversation_cycle == record.conversation.additional_attributes.fetch('jrc_acw_cycle', 0).to_i
          raise JrcContactCenter::OperationError.new('attendance_cycle_conflict', status: :conflict)
        end
      end

      now = Time.current
      duration = [(now - record.started_at).to_i, 0].max
      record.update!(attributes.slice(:reason_code, :outcome_code, :notes).merge(completed_at: now, duration_seconds: duration,
                                                                              overdue: duration >= record.acw_limit_seconds,
                                                                              exceeded_seconds: [duration - record.acw_limit_seconds, 0].max))
      record.conversation&.update!(status: :resolved)
      JrcContactCenter::AgentStateEvent.where(account: @account, account_user: @member, state: 'acw', ended_at: nil)
                                      .where("metadata ->> 'qualification_id' = ?", record.id.to_s).update_all(ended_at: now, updated_at: now)
      JrcContactCenter::FactsProjector.new(account: @account).call(record.call_session_id) if record.call_session_id
      unless JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @member)
        snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: @member)
        state_manager.record_provider_event(state: snapshot.active_call? ? 'in_call' : 'available', occurred_at: now,
                                            external_event_id: "qualification:#{record.id}:completed", provider: 'jrc_conversas', derived: true,
                                            queue_id: record.call_session&.current_queue_id, metadata: { 'qualification_id' => record.id })
      end
      record
    end
  end

  private

  def state_manager
    JrcContactCenter::AgentStateManager.new(account: @account, account_user: @member)
  end
end
