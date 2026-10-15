class JrcFlows::WorkflowTurnJob < ApplicationJob
  queue_as :default

  def perform(run_id, message_id)
    run = JrcFlowRun.find_by(id: run_id)
    return unless run && run.flow.engine == 'workflow'

    message = run.conversation.messages.incoming.where(private: false).find_by(id: message_id)
    JrcFlows::WorkflowRunner.new(run).perform(message: message) if message
  end
end

JrcFlows::WorkflowTurnJob.prepend(JrcFlows::OwnershipEntrypoints::WorkflowTurn)
