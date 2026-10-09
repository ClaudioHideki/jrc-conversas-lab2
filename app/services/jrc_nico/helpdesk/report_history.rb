# frozen_string_literal: true

class JrcNico::Helpdesk::ReportHistory
  def initialize(member)
    @context = JrcNico::Helpdesk::Context.new(member)
    @access = JrcNico::Helpdesk::ReportAccess.new(member)
  end

  def collection(policy_id:, page: 1)
    policy = @context.policy(policy_id)
    page = JrcServiceDesk::Input.id(page)
    raise ArgumentError, 'Report page is outside bounds' unless page <= 50

    visible = scope.where(policy_version_id: policy.id).order(id: :desc).limit(1000).filter_map { |report| visible_snapshot(report) }
    offset = (page - 1) * 20
    { reports: visible.slice(offset, 20) || [], page: page, next_page: visible.size > offset + 20 ? page + 1 : nil }
  end

  def find(id)
    report = scope.find(JrcServiceDesk::Input.id(id))
    snapshot(report)
  end

  private

  def scope
    JrcNico::Helpdesk::DailyReport.where(account: @context.account, recipient: @context.member)
  end

  def snapshot(report)
    @access.authorize!(report)
    receipts = JrcNico::Helpdesk::DeliveryReceipt.where(account: @context.account, recipient: @context.member,
                                                        source_type: 'daily_report', source_id: report.id).order(:id)
    report.attributes.slice('id', 'report_date', 'timezone', 'cutoff_at', 'payload').merge('receipts' => receipts.map do |receipt|
      receipt.attributes.slice('id', 'channel', 'state', 'reason', 'sent_at', 'delivered_at', 'attempt_number')
    end)
  end

  def visible_snapshot(report)
    snapshot(report)
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    nil
  end
end
