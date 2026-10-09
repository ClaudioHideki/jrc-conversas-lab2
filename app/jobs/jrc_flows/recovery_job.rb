class JrcFlows::RecoveryJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    return unless ENV['JRC_FLOWS_ENABLED'] == 'true'
    JrcFlow.active.where("settings ->> 'trigger' = ?", 'schedule').where('next_run_at <= ?', Time.current).find_each do |flow|
      flow.with_lock do
        next unless flow.status == 'active' && flow.next_run_at && flow.next_run_at <= Time.current

        scheduled_at = flow.next_run_at.to_i
        flow.account.conversations.where(display_id: Array(flow.settings['conversation_ids']), inbox_id: Array(flow.settings['inbox_ids'])).find_each do |conversation|
          JrcFlows::DispatchJob.perform_later(flow.account_id, conversation.id, 'schedule',
            "schedule:#{scheduled_at}:#{conversation.id}", nil, nil, flow.id)
        end
        flow.update_columns(next_run_at: flow.settings['interval_minutes'].to_i.minutes.from_now)
      end
    end
    JrcFlowRun.where(status: %w[waiting delayed]).where('wake_at <= ?', Time.current).find_each do |run|
      JrcFlows::ResumeJob.perform_later(run.id, run.wake_version)
    end
    JrcFlowRun.where(status: 'waiting').where('settings ? :key', key: JrcRelationship::PlaybookFlowWebhookJournal::KEY).find_each do |run|
      JrcRelationship::PlaybookFlowWebhookDelivery.recover(run) if JrcRelationship::PlaybookFlowContinuation.managed?(run)
    end
    JrcFlowRun.where(status: 'running').where('created_at < ?', 2.minutes.ago).find_each do |run|
      JrcFlows::ResumeJob.perform_later(run.id)
    end
  end
end
