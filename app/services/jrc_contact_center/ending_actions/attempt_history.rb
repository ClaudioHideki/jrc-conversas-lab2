# frozen_string_literal: true

# Bounded read path; no ensure_voice!, overdue refresh, enqueue, activation or
# implicit retry. Missing technical history is an empty list, never a fake success.
class JrcContactCenter::EndingActions::AttemptHistory
  def initialize(account:, member:, qualification_id:, page: 1, contract_version: 1)
    @account = account
    @member = member
    @qualification_id = qualification_id
    @page = page_number(page)
    @contract_version = contract_version
  end

  def call
    context = JrcContactCenter::EndingActions::HistoryContext.new(account: @account, member: @member, qualification_id: @qualification_id)
    context.call do |member, qualification|
      origins = JrcContactCenter::EndingActionOrigin.where(account: @account, source_qualification_id: qualification.id)
      page = @contract_version == 2 ? destination_page(member, origins) : legacy_page(member, origins)
      page.merge(qualification_id: qualification.id.to_s, call_session_id: qualification.call_session_id&.to_s)
    end
  end

  private

  def destination_page(member, origins)
    JrcContactCenter::EndingActions::DestinationHistoryPage.new(account: @account, member: member, origins: origins, page: @page).call
  end

  def legacy_page(member, origins)
    records = JrcContactCenter::EndingActionAttempt.where(account: @account, origin_id: origins.select(:id))
    total = records.count
    projection = JrcContactCenter::EndingActions::AttemptProjection.new(member: member)
    rows = records.order(id: :desc).offset((@page - 1) * 20).limit(20).includes(outcome: :execution)
    { items: rows.map { |row| projection.call(row) },
      meta: { page: @page, per_page: 20, total: total, pages: (total / 20.0).ceil } }
  end

  def page_number(value)
    JrcServiceDesk::Input.version(value).clamp(1, 1_000_000)
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_ending_history_page'
  end
end
