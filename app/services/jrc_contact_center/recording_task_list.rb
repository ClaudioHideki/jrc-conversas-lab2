# frozen_string_literal: true

class JrcContactCenter::RecordingTaskList
  def initialize(account:, member:, page: 1)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id

    @account = account
    @member = member
    @page = JrcServiceDesk::Input.version(page).clamp(1, 1_000_000)
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_recording_task_page'
  end

  def call(record_id)
    source = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :recordings_listen)
    source.with_record(record_id) do |record, call|
      rows = scoped_links.where(recording: record, call_session: call)
      total = rows.count
      items = rows.order(id: :desc).offset((@page - 1) * 20).limit(20).map { |row| present(row) }
      { recording_id: record.id.to_s, call_session_id: call.id.to_s, call_id: record.external_unique_id, items: items,
        timezone: Time.zone.tzinfo.name, project_module_available: JrcOperations::Access.project_access?(@member),
        meta: { page: @page, per_page: 20, total: total, pages: (total / 20.0).ceil } }
    end
  end

  private

  def scoped_links
    context = { account: @account, account_user: @member, user: @member.user }
    JrcContactCenter::RecordingTaskScope.new(context: context, relation: JrcContactCenter::RecordingTaskLink.where(account: @account)).call
  end

  def present(row)
    { id: row.id.to_s, account_user_id: row.actor_account_user_id.to_s, created_at: row.created_at.iso8601,
      request_id: row.idempotency_key, target: JrcContactCenter::EndingActions::DestinationTargetReference.new(member: @member).call(row) }
  end
end
