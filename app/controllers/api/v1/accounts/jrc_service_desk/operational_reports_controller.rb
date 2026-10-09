# frozen_string_literal: true

class Api::V1::Accounts::JrcServiceDesk::OperationalReportsController < Api::V1::Accounts::JrcServiceDesk::OperationsController
  def show
    authorize :module, :dashboard?, policy_class: ::JrcServiceDesk::ModulePolicy
    query = ::JrcServiceDesk::OperationalReportQuery.new(user_context: pundit_user, parameters: query_values)
    collection = query.collection
    render json: base_payload.merge(unit_id: query.unit.id.to_s, report: ::JrcServiceDesk::OperationalReportMetrics.new(query).call,
                                    items: collection[:items].map { |ticket| presenter.ticket(ticket) }, meta: collection[:meta])
  end

  def export
    authorize :module, :dashboard?, policy_class: ::JrcServiceDesk::ModulePolicy
    query = ::JrcServiceDesk::OperationalReportQuery.new(user_context: pundit_user, parameters: query_values)
    raise ArgumentError, 'Narrow the export to at most 10000 tickets' if query.relation.count > 10_000

    headers = %w[number title opened_at unit_id service_id category_id priority_id status origin_channel company_id]
    rows = query.relation.order(:id).map do |ticket|
      # Read through the same native authorization as the screen, not raw customer data.
      record = presenter.ticket(ticket)
      [record[:number], record[:title], ticket.opened_at.iso8601(6), record[:unit_id], record.dig(:service, :id),
       record.dig(:category, :id), record.dig(:priority, :id), record.dig(:status, :name), record[:source], record.dig(:company, :id)]
    end
    csv = ::JrcServiceDesk::OperationalCsv.generate(headers, rows)
    audit_export!(query, rows.size, Digest::SHA256.hexdigest(csv))
    send_data csv, filename: 'service-desk-tickets.csv', type: 'text/csv; charset=utf-8', disposition: 'attachment'
  end

  private

  def audit_export!(query, count, digest)
    # Associate with Unit, never Account.associated_audits (which lacks a Unit filter).
    metadata = { 'namespace' => 'jrc_sd_operational_export_v1', 'account_id' => Current.account.id,
                 'unit_id' => query.unit.id, 'account_user_id' => query.context.account_user.id,
                 'filters' => query.filters, 'count' => count, 'sha256' => digest }
    Audited::Audit.create!(auditable: query.unit, associated: query.unit, user: query.context.user, action: 'export',
                           audited_changes: {}, comment: ::JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: SecureRandom.uuid)
  end
end
