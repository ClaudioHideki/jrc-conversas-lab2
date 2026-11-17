# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::ConfigurationAuditsController < Api::V1::Accounts::JrcContactCenter::BaseController
  MAX_EXPORT_ROWS = 1000

  before_action :authorize_configuration_audit!
  before_action -> { response.headers['Cache-Control'] = 'no-store' }

  def index
    query = JrcContactCenter::ConfigurationAuditQuery.new(context: pundit_user, params: params)
    params[:page] = 1 if params[:page].blank?
    records = query.call
    presenter = JrcContactCenter::ConfigurationAuditPresenter.new(account: Current.account, records: records)
    payload = list_payload(records) { |row| presenter.call(row) }
    payload[:actors] = presenter.actors
    payload[:window] = query.window
    render json: payload
  end

  def show
    records = JrcContactCenter::ConfigurationAuditScope.new(context: pundit_user).call.where(id: params[:id])
    record = records.first!
    presenter = JrcContactCenter::ConfigurationAuditPresenter.new(account: Current.account, records: records)
    render json: base_payload.merge(item: presenter.call(record), timezone: Time.zone.tzinfo.identifier)
  end

  def export
    authorize_contact_center!(:reports?)
    records = JrcContactCenter::ConfigurationAuditQuery.new(context: pundit_user, params: params).call.limit(MAX_EXPORT_ROWS + 1)
    rows = records.to_a
    raise JrcContactCenter::OperationError, 'audit_export_limit_exceeded' if rows.length > MAX_EXPORT_ROWS

    presenter = JrcContactCenter::ConfigurationAuditPresenter.new(account: Current.account, records: records)
    csv = JrcServiceDesk::OperationalCsv.generate(export_headers, rows.map { |row| export_values(presenter.call(row)) })
    response.headers['X-Content-SHA256'] = Digest::SHA256.hexdigest(csv)
    send_data csv, type: 'text/csv; charset=utf-8', filename: "call-center-auditoria-#{Date.current.iso8601}.csv"
  end

  private

  def authorize_configuration_audit!
    authorize_contact_center!(:audit?)
    raise JrcContactCenter::OperationError.new('native_audit_unavailable', status: :not_found) unless Current.account.feature_enabled?('audit_logs')
  end

  def export_headers
    ['ID', 'Data e hora', 'Usuário ID', 'Recurso', 'Registro ID', 'Operação', 'Correlação', 'Antes', 'Depois', 'Escopo anterior', 'Escopo posterior']
  end

  def export_values(row)
    [row[:id], row[:created_at].in_time_zone.iso8601, row[:actor_id], row[:resource_type], row[:resource_id], row[:operation],
     row[:correlation_id], row[:before].to_json, row[:after].to_json, row.dig(:scopes, 'before').to_json, row.dig(:scopes, 'after').to_json]
  end
end
