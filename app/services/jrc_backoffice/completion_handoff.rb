# Locate the existing canonical portfolio and native handoff. A preview never
# creates a portfolio, prepares/accepts a handoff or executes an onboarding.
class JrcBackoffice::CompletionHandoff
  def initialize(account:, actor:, request_id:)
    @access = JrcBackoffice::ContractAccess.new(account: account, actor: actor)
    @request_id = request_id
  end

  def call
    record = @access.request(@request_id)
    record.sales_order.with_lock('FOR SHARE') do
      record.with_lock('FOR SHARE') do
        current = @access.request(record.id)
        raise JrcBackoffice::CompletionReport::NotCompleted unless current.completed? && current.stage == 'completed' && current.completed_at

        result = locate(current.sales_order)
        @access.request(record.id)
        result
      end
    end
  end

  private

  def locate(order)
    context = team_context
    assignment = context.assignments.find_by(JrcRelationship::Eligibility.new(order).identity)
    return { available: false, code: 'HANDOFF_CONTEXT_UNAVAILABLE' } unless assignment

    source = assignment.customer_context(context.member).orders.find(order.id)
    reason = JrcRelationship::Eligibility.new(source, exception: assignment.settings['eligibility_exception']).reason
    return { available: false, code: 'HANDOFF_DEPENDENCY_PENDING' } if reason

    current = team_context
    current.assignment(assignment.id).customer_context(current.member).orders.find(source.id)
    handoff_result(current, assignment, source)
  rescue Pundit::NotAuthorizedError
    { available: false, code: 'HANDOFF_PERMISSION_REQUIRED' }
  rescue ActiveRecord::RecordNotFound
    { available: false, code: 'HANDOFF_CONTEXT_UNAVAILABLE' }
  end

  def handoff_result(context, assignment, source)
    handoff = JrcRelationship::HandoffCase.where(account: context.account, assignment_id: assignment.id,
                                                 source_type: source.class.name, source_id: source.id).first
    { available: true, assignment_id: assignment.id, source_type: source.class.name, source_id: source.id,
      handoff_id: handoff&.id, handoff_status: handoff&.status }
  end

  def team_context
    context = JrcRelationship::Context.new(@access.membership!)
    raise Pundit::NotAuthorizedError unless context.policy.team?

    context
  end
end
