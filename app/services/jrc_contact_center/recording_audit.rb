# frozen_string_literal: true

# Reuses the approved configuration-audit corporate snapshot filters. A native
# recording scope is also required: audit rights never grant another call.
class JrcContactCenter::RecordingAudit < JrcContactCenter::ConfigurationAuditScope
  COMMENTS = %w[jrc_contact_center_recording_access_v1 jrc_contact_center_recording_reproduction_v1].freeze
  OPERATIONS = %w[view listen download reproduce].freeze

  def call
    allowed = @policy.audit? && @policy.recordings_view? && @account.feature_enabled?('audit_logs')
    return @relation.none unless allowed && @account.telephony_integration

    reader = JrcContactCenter::RecordedCalls.new(account: @account, member: @member)
    rows = @relation.where(associated_type: 'Account', associated_id: @account.id, comment: COMMENTS,
                           auditable_type: 'TelephonyCallRecord', auditable_id: reader.records.reselect(:id), action: 'read')
    return rows if @access.full_access? && !@organization.restricted?

    # Missing legacy snapshots remain stored, but cannot grant restricted access.
    restricted_configurations(rows)
  rescue Pabx::Error, ActiveRecord::RecordNotFound
    # A missing/disabled personal SIP association is not a recording-history grant.
    # Keep ordinary audit records available; database errors still propagate.
    @relation.none
  end

  def self.scope_fields(call)
    target = call.current_queue || call.current_unit
    scope = target ? JrcContactCenter::ConfigurationAuditSnapshot.capture(target).fetch('scope') : {}
    { 'cc_scope' => { 'before' => scope, 'after' => scope } }
  end

  def self.present(row)
    changes = row.audited_changes
    valid = changes.is_a?(Hash) && OPERATIONS.include?(changes['operation']) && row.created_at.present?
    raise JrcContactCenter::OperationError, 'invalid_recording_audit' unless valid

    { id: row.id.to_s, created_at: row.created_at.iso8601, actor_id: row.user_id&.to_s,
      operation: changes.fetch('operation'), request_id: safe_request_id(row.request_uuid) }
  end

  def self.safe_request_id(value)
    value if value.is_a?(String) && value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
  end
  private_class_method :safe_request_id
end
