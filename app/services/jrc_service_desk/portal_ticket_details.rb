# frozen_string_literal: true

class JrcServiceDesk::PortalTicketDetails
  def initialize(scope:, ticket:)
    @scope = scope
    @ticket = ticket
  end

  def call
    { sla: clocks, notification_history: deliveries, surveys: surveys }
  end

  private

  def clocks
    cycle = @ticket.sla_cycles.order(number: :desc).first
    return [] unless cycle

    cycle.sla_clocks.order(:id).map do |clock|
      JrcServiceDesk::ClockProjection.new(clock).call.slice(
        :kind, :state, :budget_seconds, :elapsed_seconds, :remaining_seconds,
        :consumed_percent, :breached, :due_at, :observed_at, :achieved_at, :timezone, :time_basis
      )
    end
  end

  def deliveries
    rows = JrcServiceDesk::NotificationDelivery.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, ticket_id: @ticket.id)
    rows.order(:id).filter_map { |row| delivery_payload(row) if delivery_allowed?(row) }
  end

  def delivery_allowed?(row)
    origin = row.ticket_note || row.ticket_event
    return false unless origin && JrcServiceDesk::NotificationSource.new(origin).publishable?
    return false unless @scope.conversations.exists?(id: row.conversation_id)

    public_message?(row)
  end

  def public_message?(row)
    message = row.message
    !message || (!message.private? && message.outgoing? && message.conversation_id == row.conversation_id)
  end

  def delivery_payload(row)
    { id: row.id.to_s, channel: row.channel, state: row.state, attempt_number: row.attempt_number,
      created_at: row.created_at.iso8601(6), updated_at: row.updated_at.iso8601(6), sent_at: row.sent_at&.iso8601(6),
      delivered_at: row.delivered_at&.iso8601(6), body: row.message&.content }
  end

  def surveys
    JrcRelationship::Survey.where(account_id: @ticket.account_id, contact_id: @scope.contact.id,
                                  source_type: 'JrcServiceDesk::Ticket', source_id: @ticket.id,
                                  status: %w[available sent delivered]).where('expires_at > ?', Time.current).filter_map do |survey|
      next if survey.responded_at || JrcRelationship::SurveyExecutionContext.new(survey).blocker

      { id: survey.id.to_s, kind: survey.kind, expires_at: survey.expires_at.iso8601(6),
        path: "/jrc/relacionamento/pesquisas/#{survey.signed_id(purpose: :relationship_survey)}" }
    end
  end
end
