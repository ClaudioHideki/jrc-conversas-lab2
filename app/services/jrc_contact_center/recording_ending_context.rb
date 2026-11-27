# frozen_string_literal: true

# Called inside the existing recording source-authority transaction. Reading a
# recording must never start ACW, create a qualification or enqueue an action.
class JrcContactCenter::RecordingEndingContext
  def initialize(account:, member:, call:, page:)
    @account = account
    @member = member
    @call = call
    @page = JrcServiceDesk::Input.version(page).clamp(1, 1_000_000)
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_history_page'
  end

  def call
    raise ActiveRecord::RecordNotFound unless @call.account_id == @account.id && @member.account_id == @account.id

    rows = authorized_records
    total = rows.count
    items = rows.order(created_at: :desc, id: :desc).offset((@page - 1) * 20).limit(20).map { |row| present(row) }
    { call_session_id: @call.id.to_s, items: items,
      meta: { page: @page, per_page: 20, total: total, pages: (total / 20.0).ceil } }
  end

  private

  def authorized_records
    context = { account: @account, account_user: @member, user: @member.user }
    access = JrcContactCenter::AccessScope.new(user_context: context)
    audit = access.full_access? && access.policy.audit?
    raise Pundit::NotAuthorizedError unless audit || access.policy.operate?

    rows = JrcContactCenter::Qualification.where(account: @account, call_session: @call)
    audit ? rows : rows.where(account_user: @member)
  end

  def present(row)
    context = JrcContactCenter::EndingActions::HistoryContext.new(account: @account, member: @member, qualification_id: row.id)
    context.call do |_member, record|
      { id: record.id.to_s, account_user_id: record.account_user_id.to_s,
        started_at: record.started_at&.iso8601, completed_at: record.completed_at&.iso8601 }
    end
  end
end
