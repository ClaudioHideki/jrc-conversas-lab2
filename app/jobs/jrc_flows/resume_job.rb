class JrcFlows::ResumeJob < ApplicationJob
  queue_as :default

  def perform(run_id, wake_version = nil)
    run = JrcFlowRun.find_by(id: run_id)
    JrcFlows::Runner.new(run).perform(wake_version: wake_version) if run
  end
end

JrcFlows::ResumeJob.prepend(JrcFlows::OwnershipEntrypoints::Resume)
