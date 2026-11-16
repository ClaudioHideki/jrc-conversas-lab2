# frozen_string_literal: true

class JrcContactCenter::AccessScope
  attr_reader :account, :account_user, :policy

  def initialize(user_context:)
    @account = user_context.fetch(:account)
    @account_user = user_context.fetch(:account_user)
    @policy = JrcContactCenter::ModulePolicy.new(user_context, :contact_center)
  end

  def full_access?
    policy.supervise? || policy.configure?
  end

  def queue_ids
    @queue_ids ||= begin
      relation = JrcContactCenter::QueueMembership.where(account: account, account_user: account_user, active: true)
      now = Time.current
      relation = relation.where('starts_at IS NULL OR starts_at <= ?', now)
      relation = relation.where('ends_at IS NULL OR ends_at > ?', now)
      relation.pluck(:queue_id)
    end
  end

  def units
    relation = organizational.units
    return relation if full_access?

    relation.where(id: JrcContactCenter::Queue.where(account: account, id: queue_ids).select(:unit_id))
  end

  def queues
    relation = JrcContactCenter::Queue.where(account: account, unit_id: organizational.units.select(:id))
    full_access? ? relation : relation.where(id: queue_ids)
  end

  def call_sessions
    relation = organizational.records(JrcContactCenter::CallSession.where(account: account),
                                      unit_column: :current_unit_id, queue_column: :current_queue_id)
    return relation if full_access?

    relation.where(id: my_call_session_ids)
  end

  def my_call_sessions
    call_sessions.where(id: my_call_session_ids)
  end

  def unassigned_call_sessions
    return JrcContactCenter::CallSession.none unless full_access?

    assigned_ids = JrcContactCenter::CallLeg
                   .where(account: account)
                   .where.not(account_user_id: nil)
                   .select(:call_session_id)
    call_sessions.where.not(id: assigned_ids)
  end

  def cases
    relation = organizational.records(JrcContactCenter::Case.where(account: account), unit_column: :unit_id, queue_column: :queue_id)
    return relation if full_access?

    relation.where(queue_id: queue_ids).or(relation.where(owner_account_user_id: account_user.id))
  end

  def callbacks
    relation = organizational.records(JrcContactCenter::Callback.where(account: account), unit_column: nil, queue_column: :queue_id)
    return relation if full_access?

    relation.where(queue_id: queue_ids).or(relation.where(owner_account_user_id: account_user.id))
  end

  def daily_facts
    relation = organizational.records(JrcContactCenter::DailyFact.where(account: account), unit_column: :unit_id, queue_column: :queue_id)
    return relation if full_access?

    relation.where(queue_id: queue_ids).or(relation.where(account_user_id: account_user.id))
  end

  def commands
    relation = JrcContactCenter::Command.where(account: account)
    relation = relation.where(call_session_id: call_sessions.select(:id)) if organizational.restricted?
    full_access? ? relation : relation.where(actor_account_user: account_user)
  end

  def events
    relation = JrcContactCenter::EventInbox.where(account: account)
    return relation unless organizational.restricted?

    # Unmapped administrative/provider events cannot be attributed to a unit
    # by guessing. Only already-authorized, provider-correlated calls qualify.
    calls = call_sessions.to_sql
    relation.where(<<~SQL.squish)
      EXISTS (SELECT 1 FROM (#{calls}) scoped_calls
        WHERE scoped_calls.provider = jrc_contact_center_event_inboxes.provider
        AND (scoped_calls.correlation_id = jrc_contact_center_event_inboxes.payload ->> 'correlation_id'
          OR scoped_calls.external_session_id = jrc_contact_center_event_inboxes.payload ->> 'call_session_id'))
    SQL
  end

  private

  def organizational
    @organizational ||= JrcContactCenter::OrganizationalScope.new(account: account, account_user: account_user)
  end

  def my_call_session_ids
    JrcContactCenter::CallLeg
      .where(account: account, account_user_id: account_user.id)
      .select(:call_session_id)
  end
end
