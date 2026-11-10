# Monitoring mode reuses native selection, authorization, idempotence and Flow
# approval. Explicit user playbooks and reviewed cadence execution retain v1.
class JrcRelationship::AutomaticPlaybooks < JrcRelationship::Playbooks
  private

  def with_step_budget(assignment, steps, execution_context, &)
    execution_context[:automatic] = true
    steps.select { |_key, step, _book| step['kind'] == 'risk' }.each do |key, step, _book|
      native_step!(assignment, step, key, execution_context)
    end
    JrcRelationship::AutomaticPlaybookBudget.new(@context, assignment).call(steps, &)
  end
end
