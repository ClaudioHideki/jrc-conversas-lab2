class JrcRelationship::PlaybookFlowResumeJob < ApplicationJob
  queue_as :default

  def perform(run_id, wake_version)
    run = JrcFlowRun.find_by(id: run_id)
    return unless run && JrcRelationship::PlaybookFlowContinuation.managed?(run)

    JrcFlows::Runner.new(run).perform(wake_version: wake_version)
  end
end
