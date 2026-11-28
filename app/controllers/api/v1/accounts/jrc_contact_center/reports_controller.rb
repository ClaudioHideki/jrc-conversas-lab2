# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::ReportsController < Api::V1::Accounts::JrcContactCenter::BaseController
  RECORDING_EXPORT_MAX_ROWS = 1000
  RECORDING_EXPORT_COLUMNS = %w[id call_session_id unit_id unit_name queue_id queue_name unique_id started_at direction status].freeze
  RECORDING_EXPORT_HEADERS = ['Gravação ID', 'Chamada ID', 'Unidade ID', 'Unidade', 'Fila ID', 'Fila', 'Identificador da chamada',
                              'Início', 'Tipo (código)', 'Resultado (código)', 'Número de origem', 'Número de destino', 'Duração (segundos)'].freeze

  before_action :private_recording_response, only: :recordings_export
  rescue_from Pabx::Error, with: :recording_export_unavailable

  def summary
    authorize_contact_center!(:reports?)
    metrics = JrcContactCenter::MetricsSummary.from_params(scope: contact_center_access.daily_facts, params: params).call
    render json: base_payload.merge(metrics: metrics)
  rescue ArgumentError
    render json: base_payload.merge(error: 'invalid_report_range'), status: :unprocessable_entity
  end

  # Metadata only. Uses the same two native recording scopes and period filters;
  # does not obtain audio bytes, public links or provider/analysis data.
  def recordings_export
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      Current.user.reload
      authorize_contact_center!(:reports?)
      member = Current.account.account_users.find_by!(user_id: Current.user.id)
      reader = JrcContactCenter::RecordedCalls.new(account: Current.account, member: member)
      records = reader.filtered(params).limit(RECORDING_EXPORT_MAX_ROWS + 1).to_a
      raise JrcContactCenter::OperationError, 'recording_export_limit_exceeded' if records.length > RECORDING_EXPORT_MAX_ROWS

      send_recording_report(reader, records)
    end
  rescue ArgumentError
    render json: base_payload.merge(error: 'invalid_recording_range'), status: :unprocessable_entity
  end

  private

  def private_recording_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def recording_export_unavailable
    render json: base_payload.merge(error: 'recording_export_unavailable'), status: :service_unavailable
  end

  def send_recording_report(reader, records)
    rows = records.map { |record| recording_report_row(reader.present(record)) }
    csv = JrcServiceDesk::OperationalCsv.generate(RECORDING_EXPORT_HEADERS, rows)
    digest = Digest::SHA256.hexdigest(csv)
    audit_recording_report!(records, digest)
    response.headers['X-Content-SHA256'] = digest
    response.headers['X-Jrc-Recording-Account'] = Current.account.id.to_s
    response.headers['X-Jrc-Recording-Count'] = records.length.to_s
    send_data csv, type: 'text/csv; charset=utf-8', filename: "call-center-gravacoes-#{Date.current.iso8601}.csv"
  end

  def recording_report_row(row)
    duration = row[:total_duration_seconds]
    duration = nil unless duration.is_a?(Numeric) && duration >= 0
    row.values_at(*RECORDING_EXPORT_COLUMNS.map(&:to_sym)) + [row.dig(:caller, :number), row.dig(:callee, :number), duration]
  end

  def audit_recording_report!(records, digest)
    Audited.audit_class.create!(
      auditable: Current.account, associated: Current.account, user: Current.user, action: 'read',
      comment: 'jrc_contact_center_recording_access_v1', audited_changes: {
        'schema_version' => 1, 'operation' => 'export', 'format' => 'csv', 'record_ids' => records.map { |record| record.id.to_s },
        'record_count' => records.length, 'sha256' => digest
      }
    )
  end
end
