# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::RecordingQualityReportsController < Api::V1::Accounts::JrcContactCenter::BaseController
  before_action :private_response

  rescue_from JrcVoiceQuality::PersistenceError, JrcVoiceQuality::ConfigurationError, Pabx::Error, with: :source_unavailable

  def index
    report = JrcContactCenter::RecordingQualityReport.new(account: Current.account, member: Current.account_user)
    report.call(params) do |reader, relation, metrics, cutoff|
      params[:page] = 1 if params[:page].blank?
      payload = list_payload(relation) { |record| reader.present(record).merge(quality: metrics.present(record.external_unique_id)) }
      audit_read!(payload)
      render json: payload.merge(period: period(reader), quality_summary: metrics.summary, observed_at: cutoff.iso8601(6),
                                 summary: reader.period_summary(relation, total: payload.dig(:meta, :total)))
    end
  rescue ArgumentError
    render json: base_payload.merge(error: 'invalid_recording_range'), status: :unprocessable_entity
  end

  private

  def period(reader)
    { from: reader.period.begin.to_date, to: reader.period.end.to_date, timezone: Time.zone.name }
  end

  def audit_read!(payload)
    Audited.audit_class.create!(auditable: Current.account, associated: Current.account, user: Current.user, action: 'read',
                               comment: 'jrc_contact_center_recording_access_v1', audited_changes: {
                                 'schema_version' => 1, 'operation' => 'quality_summary',
                                 'record_ids' => payload.fetch(:items).map { |row| row.fetch(:id) }, 'page' => payload.dig(:meta, :page)
                               })
  end

  def private_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def source_unavailable
    render json: base_payload.merge(error: 'quality_summary_source_unavailable'), status: :service_unavailable
  end
end
