# frozen_string_literal: true

class JrcContactCenter::DeferredPauseAudit
  COMMENT = 'jrc_contact_center_deferred_pause_v1'

  def self.write!(record, before:, automatic: false)
    Audited.audit_class.create!(
      auditable: record, associated: record.account, user: automatic ? nil : record.account_user.user,
      action: before ? 'update' : 'create', comment: COMMENT,
      audited_changes: { 'state' => [before, record.state], 'request_id' => record.request_id,
                         'failure_code' => record.failure_code, 'local_only' => true }
    )
  end
end
