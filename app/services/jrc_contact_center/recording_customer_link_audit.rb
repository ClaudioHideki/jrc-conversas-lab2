# frozen_string_literal: true

# Keep customer identifiers out of the ordinary account audit list. Each read
# intersects the existing recording, current call, directory and historical scopes.
class JrcContactCenter::RecordingCustomerLinkAudit < JrcContactCenter::RecordingAudit
  COMMENT = JrcContactCenter::RecordingCustomerLink::COMMENT

  def call
    return @relation.none unless history_available? && @policy.operate? && @policy.recordings_listen?

    contacts = authorized_contact_ids_sql
    reader = JrcContactCenter::RecordedCalls.new(account: @account, member: @member)
    recordings = reader.records.reselect(Arel.sql('telephony_call_records.id::text')).to_sql
    rows = @relation.where(associated_type: 'Account', associated_id: @account.id, comment: COMMENT,
                           auditable_type: 'JrcContactCenter::CallSession', auditable_id: reader.calls.reselect(:id), action: 'update')
    rows = rows.where("audits.audited_changes ->> 'recording_id' IN (#{recordings})")
    rows = rows.where("audits.audited_changes -> 'after' ->> 'contact_id' IN (#{contacts})")
    return rows if @access.full_access? && !@organization.restricted?

    restricted_configurations(rows)
  rescue Pundit::NotAuthorizedError, Pabx::Error, ActiveRecord::RecordNotFound
    @relation.none
  end

  private

  def authorized_contact_ids_sql
    directory = JrcCustomers::ContactDirectory.new(account: @account, actor: @member.user)
    directory.scope.reselect(Arel.sql('contacts.id::text')).to_sql
  end
end
