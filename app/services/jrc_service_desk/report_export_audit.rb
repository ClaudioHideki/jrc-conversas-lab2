# frozen_string_literal: true

class JrcServiceDesk::ReportExportAudit
  def self.call(export, result, user)
    metadata = { namespace: 'jrc_sd_report_export_v2', export_id: export.id, report: 'operational', format: export.format,
                 result: result, account_id: export.account_id, unit_id: export.unit_id, account_user_id: export.account_user_id,
                 filters: export.filters, count: export.record_count, expected_count: export.expected_count, occurred_at: Time.current.iso8601(6),
                 error_code: export.error_code }
    Audited::Audit.create!(auditable: export.unit, associated: export.unit, user: user, action: 'export', audited_changes: {},
                           comment: JrcServiceDesk::CanonicalJson.dump(metadata), request_uuid: SecureRandom.uuid)
  end
end
