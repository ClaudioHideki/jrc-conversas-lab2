# frozen_string_literal: true

class JrcContactCenter::ConfigurationAuditQuery
  TYPES = {
    'unit' => 'JrcContactCenter::Unit', 'queue' => 'JrcContactCenter::Queue',
    'membership' => 'JrcContactCenter::QueueMembership', 'role' => 'CustomRole', 'access' => 'JrcContactCenter::AccessGrant'
  }.freeze

  FILTER_KEYS = %i[from to resource_type resource_id operation actor_id unit_id correlation_id history page per_page].freeze

  attr_reader :from, :through

  def history?
    @params[:history] == 'true'
  end

  def initialize(context:, params:)
    @context = context
    @params = params
    validate_scalar_filters!
    history? ? validate_history! : read_window!
  end

  def call
    records = JrcContactCenter::ConfigurationAuditScope.new(context: @context).call
    records = records.where(created_at: from.in_time_zone...((through + 1).in_time_zone)) unless history?
    records = resource_filter(records)
    records = action_filter(records)
    records = unit_filter(records)
    records = records.where(user_id: @params[:actor_id]) if @params[:actor_id].present?
    records = records.where(request_uuid: @params[:correlation_id].to_s.first(100)) if @params[:correlation_id].present?
    records.order(created_at: :desc, id: :desc)
  end

  def window
    { from: from&.iso8601, to: through&.iso8601, history: history?, timezone: Time.zone.tzinfo.identifier }
  end

  private

  def validate_scalar_filters!
    malformed = @params.slice(*FILTER_KEYS).values.any? { |value| !value.nil? && !value.is_a?(String) }
    raise JrcContactCenter::OperationError, 'invalid_audit_filter' if malformed
  end

  def read_window!
    @from = Date.iso8601(@params[:from].presence || 29.days.ago.to_date.iso8601)
    @through = Date.iso8601(@params[:to].presence || Date.current.iso8601)
    raise JrcContactCenter::OperationError, 'invalid_audit_dates' if @from > @through
  rescue Date::Error
    raise JrcContactCenter::OperationError, 'invalid_audit_dates'
  end

  def validate_history!
    valid = TYPES.key?(@params[:resource_type]) && @params[:resource_id].to_s.match?(/\A[1-9]\d*\z/)
    raise JrcContactCenter::OperationError, 'invalid_audit_filter' unless valid
  end

  def resource_filter(records)
    key = @params[:resource_type].presence
    if key
      type = TYPES[key]
      raise JrcContactCenter::OperationError, 'invalid_audit_filter' unless type

      records = records.where(auditable_type: type)
    end
    records = records.where(auditable_id: @params[:resource_id]) if @params[:resource_id].present?
    records
  end

  def action_filter(records)
    value = @params[:operation].presence
    return records unless value

    raise JrcContactCenter::OperationError, 'invalid_audit_filter' unless %w[create update destroy].include?(value)

    records.where(action: value)
  end

  def unit_filter(records)
    return records if @params[:unit_id].blank?

    access = JrcContactCenter::AccessScope.new(user_context: @context)
    unit = access.units.find(@params[:unit_id])
    records.where(<<~SQL.squish, id: unit.id.to_s)
      audited_changes -> 'cc_scope' -> 'before' ->> 'unit_id' = :id
      OR audited_changes -> 'cc_scope' -> 'after' ->> 'unit_id' = :id
    SQL
  end
end
