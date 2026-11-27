class JrcCampaigns::ReportService
  def initialize(campaign, page: 1, per_page: 50)
    @campaign = campaign
    @page = [page.to_i, 1].max
    @per_page = per_page.to_i.clamp(1, 200)
  end

  def as_json
    scope = campaign.recipients.includes(:contact, :inbox, :execution, :deliveries).order(id: :desc)
    total = scope.count
    recipients = scope.offset((page - 1) * per_page).limit(per_page).to_a
    @provider_error_codes = provider_error_codes(recipients)

    {
      timezone: campaign.sending_window['timezone'].presence || 'UTC',
      summary: summary,
      executions: campaign.executions.map { |execution| execution_json(execution) },
      recipients: recipients.map { |recipient| recipient_json(recipient) },
      pagination: { page: page, per_page: per_page, total: total, pages: (total.to_f / per_page).ceil }
    }
  end

  private

  attr_reader :campaign, :page, :per_page

  def summary
    {
      total: campaign.recipients.count,
      sent: campaign.recipients.where.not(sent_at: nil).count,
      failed: campaign.recipients.where(status: 'failed').count,
      delivered: campaign.recipients.where.not(delivered_at: nil).count,
      read: campaign.recipients.where.not(read_at: nil).count,
      replied: campaign.recipients.where.not(replied_at: nil).count
    }
  end

  def execution_json(execution)
    execution.as_json(only: [:id, :run_number, :status, :total_count, :sent_count, :failed_count, :delivered_count, :read_count, :replied_count,
                             :started_at, :completed_at])
  end

  def provider_error_codes(recipients)
    deliveries = recipients.flat_map(&:deliveries).select { |delivery| delivery.failed? && delivery.external_id.present? }
    return {} if deliveries.empty?

    events = JrcCampaigns::StatusEvent.joins(:inbox)
                                      .where(inboxes: { account_id: campaign.account_id },
                                             inbox_id: deliveries.map(&:inbox_id), external_id: deliveries.map(&:external_id), status: 'failed')
                                      .order(id: :desc)
    events.pluck(:inbox_id, :external_id, :provider_errors).each_with_object({}) do |(inbox_id, external_id, errors), result|
      code = Array(errors).first.to_h['code'].presence
      result[[inbox_id, external_id]] ||= code.to_s if code
    end
  end

  def recipient_error_code(recipient)
    delivery = recipient.deliveries.select(&:failed?).max_by(&:id)
    @provider_error_codes[[delivery.inbox_id, delivery.external_id]] if delivery
  end

  def recipient_json(recipient)
    recipient.as_json(only: [:id, :name, :phone_number, :email, :destination, :source, :status, :scheduled_at, :sent_at, :delivered_at, :read_at,
                             :replied_at,
                             :failed_at, :error_message]).merge(
                               error_code: recipient_error_code(recipient),
                               contact_id: recipient.contact_id,
                               inbox_id: recipient.inbox_id,
                               inbox_name: recipient.inbox&.name,
                               deliveries: recipient.deliveries.map do |delivery|
                                 delivery.as_json(only: [:id, :step_id, :status, :external_id, :error_message, :metadata])
                               end,
                               execution_number: recipient.execution&.run_number
                             )
  end
end
