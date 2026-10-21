# frozen_string_literal: true

class JrcContactCenter::CallLegJourney
  def initialize(event_record:, session:)
    @event = event_record
    @session = session
    @account = event_record.account
    body = event_record.payload['payload']
    @data = (body.is_a?(Hash) ? body : {}).merge(event_record.payload.except('payload'))
  end

  def apply(status)
    return if @data['leg_id'].blank?

    leg = @session.legs.find_or_initialize_by(external_leg_id: @data.fetch('leg_id'))
    attributes = identity(leg)
    attributes.merge!(timing(leg, status))
    leg.assign_attributes(attributes)
    leg.save!
    leg
  end

  def close_all
    @session.legs.where.not(status: %w[ended transferred failed]).find_each do |leg|
      leg.update!(status: 'ended', ended_at: @session.ended_at)
    end
  end

  private

  def identity(leg)
    {
      account: @account,
      queue: reference(JrcContactCenter::Queue.where(account: @account), 'queue_id', leg.queue),
      account_user: reference(@account.account_users, 'account_user_id', leg.account_user),
      parent_leg: parent_leg(leg),
      direction: leg.direction.presence || @data.fetch('direction', @session.direction),
      started_at: leg.started_at || @event.occurred_at
    }
  end

  def reference(scope, key, existing)
    @data[key].present? ? scope.find(@data[key]) : existing
  end

  def parent_leg(leg)
    @data['parent_leg_id'].present? ? @session.legs.find_by!(external_leg_id: @data['parent_leg_id']) : leg.parent_leg
  end

  def timing(leg, status)
    terminal = %w[ended transferred failed].include?(leg.status)
    attributes = { status: terminal ? leg.status : status }
    attributes[:answered_at] = leg.answered_at || @event.occurred_at if status == 'connected'
    attributes[:ended_at] = leg.ended_at || @event.occurred_at if %w[ended transferred failed].include?(status)
    if root_closed_leg?(terminal)
      attributes[:status] = 'ended'
      attributes[:ended_at] = @session.ended_at
    end
    attributes
  end

  def root_closed_leg?(terminal)
    !terminal && %w[ended failed].include?(@session.status)
  end
end
