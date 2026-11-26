# frozen_string_literal: true

# Reuses both native scopes. Similar phone numbers or provider aliases never establish a recording's origin.
class JrcContactCenter::RecordedCalls
  attr_reader :period

  def initialize(account:, member:)
    @account = account
    @member = member
    context = { account: account, account_user: member, user: member.user }
    @access = JrcContactCenter::AccessScope.new(user_context: context)
  end

  def records
    authorize!(:view)
    native = Pabx::Access.new(account: @account, user: @member.user).records
    native.where(has_recording: true, external_unique_id: calls.select(:external_session_id))
  end

  def calls
    @access.call_sessions.where(provider: Pabx::Settings::PROVIDER).where.not(external_session_id: nil)
  end

  def find(id, action: :view)
    authorize!(action)
    record = records.find(id)
    [record, calls.find_by!(external_session_id: record.external_unique_id)]
  end

  def filtered(params)
    @period = period_for(params)
    relation = records.where(started_at: @period)
    search(with_operating_filters(relation, params), params[:q]).order(started_at: :desc, id: :desc)
  end

  def with_operating_filters(relation, params)
    %w[unit queue].each do |kind|
      next if params["#{kind}_id"].blank?

      scope = @access.public_send("#{kind}s")
      id = scope.find(identifier!(params["#{kind}_id"])).id
      matching = calls.where("current_#{kind}_id" => id).select(:external_session_id)
      relation = relation.where(external_unique_id: matching)
    end
    relation
  end

  def search(relation, value)
    query = value.to_s.strip.first(100)
    return relation if query.blank?

    escaped = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    relation.where('external_unique_id ILIKE :q OR caller ILIKE :q OR callee ILIKE :q', q: escaped)
  end

  def present(record)
    call = calls.find_by!(external_session_id: record.external_unique_id)
    verify_links!(call)

    settings = Pabx::Settings.new(@account.telephony_integration)
    record.public_payload(settings: settings).merge(
      id: record.id.to_s, call_session_id: call.id.to_s, unit_id: call.current_unit_id&.to_s, queue_id: call.current_queue_id&.to_s,
      unit_name: call.current_unit&.name, queue_name: call.current_queue&.name
    )
  end

  private

  def verify_links!(call)
    links = [call.current_unit, call.current_queue].compact
    raise ActiveRecord::RecordNotFound unless links.all? { |link| link.account_id == @account.id }
  end

  def authorize!(action)
    allowed = @access.policy.public_send("recordings_#{action}?") && @member.user.active_for_authentication?
    raise Pundit::NotAuthorizedError unless allowed
  end

  def identifier!(value)
    valid = (value.is_a?(String) || value.is_a?(Integer)) && value.to_s.match?(/\A[1-9][0-9]{0,18}\z/)
    raise JrcContactCenter::OperationError, 'invalid_recording_filter' unless valid && value.to_i <= 9_223_372_036_854_775_807

    value
  end

  def period_for(params)
    last = params[:to].present? ? Date.iso8601(params[:to].to_s) : Time.zone.today
    first = params[:from].present? ? Date.iso8601(params[:from].to_s) : last - 6
    raise ArgumentError, 'invalid recording period' if first > last || (last - first).to_i >= 31

    first.in_time_zone.beginning_of_day..last.in_time_zone.end_of_day
  end
end
