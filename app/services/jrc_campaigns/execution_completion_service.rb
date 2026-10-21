class JrcCampaigns::ExecutionCompletionService
  def initialize(execution)
    @execution = execution
    @campaign = execution.campaign
  end

  def check!
    execution.refresh_counters!
    campaign.refresh_counters!
    return if campaign.paused? || campaign.canceled?
    return if execution.recipients.where(status: %w[queued processing]).exists?
    return if execution.recipients.where("metadata ? 'pending_step_id'").exists?

    execution.update!(status: 'completed', completed_at: Time.current)
    JrcCampaigns::EventLogger.call(campaign: campaign, execution: execution, event_type: 'execution_completed')
    schedule_recurrence_or_complete
  end

  private

  attr_reader :execution, :campaign

  def schedule_recurrence_or_complete
    next_time = JrcCampaigns::RecurrenceService.new(campaign).next_time
    if next_time
      campaign.update!(status: 'scheduled', scheduled_at: next_time)
      JrcCampaigns::LaunchJob.set(wait_until: next_time).perform_later(campaign.id, next_time.to_i)
    else
      campaign.update!(status: 'completed', completed_at: Time.current)
    end
  end
end
