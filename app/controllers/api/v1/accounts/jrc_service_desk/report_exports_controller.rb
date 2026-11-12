# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::ReportExportsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def index
    authorize ::JrcServiceDesk::ReportExport, :index?
    query = ::JrcServiceDesk::OperationalReportQuery.new(user_context: pundit_user, parameters: query_values.slice('unit_id'),
                                                         permission: 'reports_export')
    rows = owned.where(unit_id: query.unit.id).where('expires_at > ?', Time.current).order(id: :desc).limit(20)
    render json: base_payload.merge(unit_id: query.unit.id.to_s, items: rows.map { |row| payload(row) })
  end

  def create
    values = body_values(%w[format filters expected_count])
    format = values.fetch('format')
    raise ArgumentError unless ::JrcServiceDesk::ReportExport::FORMATS.include?(format)

    query = ::JrcServiceDesk::OperationalReportQuery.new(user_context: pundit_user, parameters: values.fetch('filters'), permission: 'reports_export')
    expected = ::JrcServiceDesk::Input.version(values.fetch('expected_count'))
    raise ArgumentError, 'Export limit exceeded' if expected > ::JrcServiceDesk::ReportExport.limit_for(format)
    raise ::JrcServiceDesk::IdempotencyConflict unless expected == query.relation.count

    export = ::JrcServiceDesk::ReportExport.new(account: Current.account, unit: query.unit, account_user: query.context.account_user,
                                                format: format, expected_count: expected, filters: query.filters.except('page', 'per_page'),
                                                expires_at: 24.hours.from_now)
    authorize export, :create?
    export.save!
    ::JrcServiceDesk::ReportExportAudit.call(export, 'requested', query.context.user)
    enqueue(export)
    render json: payload(export), status: :accepted
  end

  def download
    export = owned.find(::JrcServiceDesk::Input.id(params[:id]))
    authorize export, :show?
    raise ArgumentError unless export.state == 'ready' && export.file.attached?

    ::JrcServiceDesk::ReportExportAccess.new(export, pundit_user).verify!
    blob = export.file.blob
    user = current_user
    response.headers['Content-Type'] = blob.content_type
    response.headers['Content-Length'] = blob.byte_size.to_s
    response.headers['Content-Disposition'] = ActionDispatch::Http::ContentDisposition.format(disposition: 'attachment', filename: blob.filename.to_s)
    download_audited = false
    self.response_body = Enumerator.new do |chunks|
      blob.open do |file|
        while (chunk = file.read(64.kilobytes))
          chunks << chunk
        end
      end
      unless download_audited
        ::JrcServiceDesk::ReportExportAudit.call(export, 'downloaded', user)
        download_audited = true
      end
    end
  end

  private

  def enqueue(export)
    job = ::JrcServiceDesk::ReportExportJob.perform_later(export.id)
    raise ActiveJob::EnqueueError, 'Export queue unavailable' unless job
  rescue StandardError => error
    export.update!(state: 'failed', error_code: 'queue_unavailable')
    ::JrcServiceDesk::ReportExportAudit.call(export, 'failed', export.account_user.user)
    Rails.logger.error("service_desk_export_enqueue_failed export=#{export.id} class=#{error.class.name}")
  end

  def owned
    policy_scope(::JrcServiceDesk::ReportExport)
  end

  def payload(row)
    base_payload.merge(id: row.id.to_s, unit_id: row.unit_id.to_s, state: row.expires_at <= Time.current ? 'expired' : row.state,
                       format: row.format, count: row.record_count, expected_count: row.expected_count, error_code: row.error_code,
                       observed_at: row.observed_at&.iso8601(6), expires_at: row.expires_at.iso8601(6),
                       filename: row.file.attached? ? row.file.filename.to_s : nil)
  end
end
