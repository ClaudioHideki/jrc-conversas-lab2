# frozen_string_literal: true

# SharedSurvey decisions and real dispatch timestamps remain distinct from public link availability.
class JrcNico::Helpdesk::KpiSurveyEvidence
  def initialize(context, until_at)
    @context = context
    @until = until_at
  end

  def call(cohort)
    source = JrcRelationship::Context.new(@context.member)
    scope = source.records(JrcRelationship::Survey).where(source_type: 'JrcServiceDesk::Ticket')
    rows = cohort.map { |close| survey_cycle(scope, close) }
    { 'eligible_decisions' => rows.pluck(:decision).compact.tally, 'survey_ids' => rows.flat_map { |row| row[:ids] },
      'closure_ids' => cohort.map(&:id), 'sampling_authority' => 'native_survey_policy', 'scheduled_is_sent' => false }
      .merge(%i[responded scheduled sent expired].index_with { |key| rows.count { |row| row[key] } }.stringify_keys)
  end

  private

  def survey_cycle(scope, close)
    cycle = closure_cycle(close)
    records = scope.where(source_id: close.ticket_id, cycle_key: cycle)
    decision = JrcRelationship::SurveyDispatchDecision.find_by(account: @context.account, source_type: 'JrcServiceDesk::Ticket',
                                                               source_id: close.ticket_id, cycle_key: cycle)
    { sent: records.where('sent_at <= ?', @until).exists?(status: %w[sent delivered responded]),
      responded: records.exists?(['responded_at <= ?', @until]), scheduled: records.exists?(status: 'scheduled'),
      expired: records.exists?(status: 'expired'), ids: records.pluck(:id), decision: decision&.state }
  end

  def closure_cycle(close)
    reopening = JrcServiceDesk::LifecycleTransition.where(account: @context.account, ticket_id: close.ticket_id, action: 'reopen')
                                                   .where('occurred_at <= ?', close.occurred_at).order(:occurred_at, :id).last
    "service-desk:ticket:#{close.ticket_id}:cycle:#{reopening&.id || 'initial'}"
  end
end
