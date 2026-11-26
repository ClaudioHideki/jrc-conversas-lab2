# frozen_string_literal: true

# The native current-call reader is required by callers; historical unit/company coverage also remains required.
class JrcContactCenter::QualityReviewScope < JrcContactCenter::ConfigurationAuditScope
  def call
    return @relation.none unless @policy.recordings_listen?

    rows = @relation.where(account_id: @account.id, call_session_id: @access.call_sessions.select(:id))
    return rows if @access.full_access? && !@organization.restricted?

    restricted_configurations(rows)
  end

  private

  def scope_json(_side)
    'jrc_contact_center_quality_review_revisions.scope_snapshot'
  end
end
