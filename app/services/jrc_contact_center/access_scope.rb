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
    relation = JrcContactCenter::Unit.where(account: account)
    return relation if full_access?

    relation.where(id: JrcContactCenter::Queue.where(account: account, id: queue_ids).select(:unit_id))
  end

  def queues
    relation = JrcContactCenter::Queue.where(account: account)
    full_access? ? relation : relation.where(id: queue_ids)
  end

  def call_sessions
    relation = JrcContactCenter::CallSession.where(account: account)
    return relation if full_access?

    relation.where(id: my_call_session_ids)
  end

  def my_call_sessions
    JrcContactCenter::CallSession.where(account: account, id: my_call_session_ids)
  end

  def unassigned_call_sessions
    return JrcContactCenter::CallSession.none unless full_access?

    assigned_ids = JrcContactCenter::CallLeg
                   .where(account: account)
                   .where.not(account_user_id: nil)
                   .select(:call_session_id)
    JrcContactCenter::CallSession.where(account: account).where.not(id: assigned_ids)
  end

  def cases
    relation = JrcContactCenter::Case.where(account: account)
    return relation if full_access?

    relation.where(queue_id: queue_ids).or(relation.where(owner_account_user_id: account_user.id))
  end

  def callbacks
    relation = JrcContactCenter::Callback.where(account: account)
    return relation if full_access?

    relation.where(queue_id: queue_ids).or(relation.where(owner_account_user_id: account_user.id))
  end

  def daily_facts
    relation = JrcContactCenter::DailyFact.where(account: account)
    return relation if full_access?

    relation.where(queue_id: queue_ids).or(relation.where(account_user_id: account_user.id))
  end

  private

  def my_call_session_ids
    JrcContactCenter::CallLeg
      .where(account: account, account_user_id: account_user.id)
      .select(:call_session_id)
  end
end
