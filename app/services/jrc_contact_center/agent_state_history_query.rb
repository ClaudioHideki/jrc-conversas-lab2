# frozen_string_literal: true

class JrcContactCenter::AgentStateHistoryQuery
  FILTERS = %i[from to state queue_id account_user_id q page per_page].freeze

  def initialize(access:, params:)
    @access = access
    @params = params
    invalid = params.slice(*FILTERS).values.any? { |value| !value.nil? && !value.is_a?(String) }
    raise JrcContactCenter::OperationError, 'invalid_state_history_filter' if invalid

    read_window!
  end

  def call
    records = @access.agent_state_events.where(started_at: @from.in_time_zone...((@through + 1).in_time_zone))
    records = filter_state(records)
    records = filter_queue(records)
    records = filter_member(records)
    records = filter_name(records)
    records.includes(:queue, account_user: :user).order(started_at: :desc, id: :desc)
  end

  def window
    { from: @from.iso8601, to: @through.iso8601, timezone: Time.zone.tzinfo.identifier }
  end

  private

  def read_window!
    @from = Date.iso8601(@params[:from].presence || 6.days.ago.to_date.iso8601)
    @through = Date.iso8601(@params[:to].presence || Date.current.iso8601)
    raise JrcContactCenter::OperationError, 'invalid_state_history_dates' unless valid_window?
  rescue Date::Error
    raise JrcContactCenter::OperationError, 'invalid_state_history_dates'
  end

  def valid_window?
    @from.year.positive? && @through.year <= 9999 && @from <= @through && (@through - @from) <= 30
  end

  def filter_state(records)
    return records if @params[:state].blank?

    valid = JrcContactCenter::AgentStateEvent::STATES.include?(@params[:state])
    raise JrcContactCenter::OperationError, 'invalid_state_history_filter' unless valid

    records.where(state: @params[:state])
  end

  def filter_name(records)
    return records if @params[:q].blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@params[:q].strip.first(100))}%"
    records.joins(account_user: :user).where('users.name ILIKE ?', pattern)
  end

  def filter_queue(records)
    return records if @params[:queue_id].blank?

    id = identifier!(:queue_id)
    queue = @access.queues.find(id)
    records.where(queue_id: queue.id)
  end

  def filter_member(records)
    return records if @params[:account_user_id].blank?

    records.where(account_user_id: identifier!(:account_user_id))
  end

  def identifier!(key)
    value = @params[key]
    valid = value.match?(/\A[1-9]\d{0,18}\z/) && value.to_i <= 9_223_372_036_854_775_807
    raise JrcContactCenter::OperationError, 'invalid_state_history_filter' unless valid

    value
  end
end
