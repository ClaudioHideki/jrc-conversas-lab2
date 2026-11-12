# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::SatisfactionReportsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def show
    authorize :module, :show?, policy_class: ::JrcServiceDesk::ModulePolicy
    query = ::JrcServiceDesk::SurveyReportQuery.new(user_context: pundit_user, parameters: query_values)
    page = ::JrcServiceDesk::Input.version(query.filters.fetch('page', 1))
    raise ArgumentError unless page.between?(1, 100_000)

    render json: base_payload.merge(unit_id: query.unit.id.to_s, timezone: query.timezone, filters: query.filters,
                                    summary: query.summary, distribution: query.distribution, services: query.services,
                                    items: query.responses(limit: 25, offset: (page - 1) * 25),
                                    meta: { page: page, per_page: 25, total: query.answered.count })
  end

  def export
    authorize :module, :show?, policy_class: ::JrcServiceDesk::ModulePolicy
    query = ::JrcServiceDesk::SurveyReportQuery.new(user_context: pundit_user, parameters: query_values)
    context = query.operational
    raise Pundit::NotAuthorizedError unless context.reporting_allowed?(permission: 'reports_export', unit: query.unit)

    count = query.answered.count
    raise ArgumentError, 'Select a smaller period (maximum 10000 responses)' if count > 10_000

    rows = query.responses(limit: 10_000).map do |row|
      [row[:responded_at], row.dig(:company, :name), row[:ticket_number], row.dig(:service, :name), row[:kind], row[:score], row[:comment]]
    end
    data = ::JrcServiceDesk::OperationalCsv.generate(%w[responded_at company ticket service type score comment], rows)
    metadata = { namespace: 'jrc_sd_satisfaction_export_v1', format: 'csv', result: 'completed', filters: query.filters,
                 account_id: Current.account.id, unit_id: query.unit.id, account_user_id: context.account_user.id, count: rows.length,
                 sha256: Digest::SHA256.hexdigest(data) }
    Audited::Audit.create!(auditable: query.unit, associated: query.unit, user: context.user, action: 'export', audited_changes: {},
                           comment: ::JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: SecureRandom.uuid)
    send_data "\uFEFF#{data}", type: 'text/csv; charset=utf-8', disposition: 'attachment', filename: 'JRC_ServiceDesk_Satisfacao.csv'
  end
end
