# frozen_string_literal: true

class JrcContactCenter::AgentStateSnapshot
  TERMINAL_LEG_STATES = %w[transferred ended failed].freeze

  def initialize(account_user:, adapter: nil)
    @member = account_user
    @account = account_user.account
    @adapter = adapter || JrcContactCenter::Providers::JrcPabxAdapter.new(account: @account)
  end

  def current
    @current ||= JrcContactCenter::AgentStateEvent.where(account: @account, account_user: @member)
                                                  .order(started_at: :desc, id: :desc).first
  end

  def version
    current&.id.to_s.presence || '0'
  end

  def active_call?
    JrcContactCenter::CallLeg.where(account: @account, account_user: @member).where.not(status: TERMINAL_LEG_STATES)
                             .joins(:call_session).merge(JrcContactCenter::CallSession.where.not(status: %w[ended failed])).exists?
  end

  def memberships
    now = Time.current
    JrcContactCenter::QueueMembership.where(account: @account, account_user: @member, active: true, role: 'agent')
                                     .joins(queue: :unit).where(jrc_contact_center_queues: { status: 'active' },
                                                                jrc_contact_center_units: { status: 'active' })
                                     .where('starts_at IS NULL OR starts_at <= ?', now)
                                     .where('ends_at IS NULL OR ends_at > ?', now)
                                     .where('jrc_contact_center_queues.active_from IS NULL OR jrc_contact_center_queues.active_from <= ?', now)
                                     .where('jrc_contact_center_queues.active_until IS NULL OR jrc_contact_center_queues.active_until > ?', now)
  end

  def call
    reason = eligibility_reason
    state_payload.merge(
      eligible: reason.nil?, eligibility_reason: reason,
      eligible_queue_ids: reason.nil? ? [current.queue_id.to_s] : [],
      queues: memberships.includes(:queue).map { |membership| { id: membership.queue_id.to_s, name: membership.queue.name } },
      pending_qualifications: pending_qualifications.includes(account_user: :user).map(&:operational_payload)
    )
  end

  private

  def pending_qualifications
    @pending_qualifications ||= JrcContactCenter::Qualification.pending.where(account: @account, account_user: @member).order(:started_at)
  end

  def state_payload
    {
      account_user_id: @member.id.to_s, state: pending_qualifications.exists? ? 'acw' : current&.state || 'offline', state_version: version,
      reason_code: current&.reason_code, started_at: current&.started_at, source: current&.source,
      provider_confirmed: provider_confirmed?, logged_in: current.present? && %w[offline unavailable].exclude?(current.state)
    }
  end

  def provider_confirmed?
    return false if pending_qualifications.exists?

    current&.source == @adapter.provider_key && current.metadata['provider_confirmed'] == true
  end

  def eligibility_reason
    return 'tabulation_pending' if pending_qualifications.exists?
    return 'agent_not_available' unless current&.state == 'available'
    return 'call_active' if active_call?
    return 'queue_membership_missing' unless memberships.exists?

    provider_eligibility_reason
  end

  def provider_eligibility_reason
    return 'provider_pending' unless %w[agent_states acd_queues].all? { |key| @adapter.capabilities[key] == 'available' }
    return 'provider_unconfirmed' unless provider_confirmed?
    return 'queue_login_unconfirmed' unless current.queue_id && memberships.exists?(queue_id: current.queue_id)

    nil
  end
end
