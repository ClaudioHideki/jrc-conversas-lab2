# frozen_string_literal: true

class JrcNico::Helpdesk::ReportResources
  def initialize(context, payload)
    @context = context
    @payload = payload.deep_stringify_keys
  end

  def call
    resources = @payload.fetch('ticket_ids').map { |id| ['JrcServiceDesk::Ticket', id] }
    metrics = @payload.dig('kpis', 'metrics') || []
    resources += metrics.flat_map { |metric| metric_resources(metric.fetch('evidence')) }
    resources.uniq.each { |type, id| JrcNico::DomainAccess.authorize_resource!(@context.access, type, id) }
  end

  private

  def metric_resources(evidence)
    closures = Array(evidence['closure_ids']).map { |id| ['JrcServiceDesk::LifecycleTransition', id] }
    surveys = Array(evidence['survey_ids']).map { |id| ['JrcRelationship::Survey', id] }
    closures + surveys + clock_resources(evidence)
  end

  def clock_resources(evidence)
    ids = Array(evidence['clock_ids']) + Array(evidence['observations']).flat_map { |row| Array(row['samples']).pluck('clock_id').compact }
    ids.uniq.map do |id|
      clock = JrcServiceDesk::SlaClock.where(account: @context.account).find(id)
      ['JrcNico::ServiceTicketSla', clock.ticket_id]
    end
  end
end
