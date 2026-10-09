class JrcRelationship::PlaybookFlowWebhookJob < ApplicationJob
  queue_as :default

  def perform(run_id, node_id)
    run = JrcFlowRun.find_by(id: run_id)
    return unless run && JrcRelationship::PlaybookFlowContinuation.managed?(run)

    JrcRelationship::PlaybookFlowWebhookDelivery.new(run, node_id).perform
  end
end
