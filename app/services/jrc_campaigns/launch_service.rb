class JrcCampaigns::LaunchService
  def initialize(campaign)
    @campaign = campaign
  end

  def perform
    campaign.reload
    return if stopped?
    return campaign.latest_execution if running_execution?

    recovery_state = campaign.attributes.slice('account_id', 'status', 'updated_at')
    prepared = JrcCampaigns::ApprovalService.new(campaign).prepare_validation!
    campaign.with_lock do
      next if stopped?
      next campaign.latest_execution if running_execution?

      campaign.ensure_approved!(prepared: prepared)
      start_execution!
    end
  rescue StandardError => e
    recover_failure(e, recovery_state)
    raise
  end

  private

  attr_reader :campaign

  def stopped?
    campaign.canceled? || campaign.paused? || campaign.completed?
  end

  def running_execution?
    campaign.running? && campaign.latest_execution&.running?
  end

  def start_execution!
    campaign.update!(status: 'running', started_at: campaign.started_at || Time.current, last_execution_at: Time.current, last_error: nil)
    execution = campaign.executions.create!(
      run_number: campaign.executions.maximum(:run_number).to_i + 1,
      status: 'running',
      started_at: Time.current
    )
    build_recipients(execution)
    schedule_recipients(execution)
    JrcCampaigns::EventLogger.call(campaign: campaign, execution: execution, event_type: 'execution_started')
    execution
  end

  def recover_failure(error, expected_state)
    return unless expected_state

    # A failed remote read cannot undo a newer pause/cancellation or another launch.
    JrcCampaigns::Campaign.where(expected_state.merge('id' => campaign.id))
                          .update_all(status: 'draft', last_error: error.message, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def build_recipients(execution)
    rotation = JrcCampaigns::RotationSelector.new(campaign)

    campaign.review_snapshot.fetch('recipients').each_with_index do |entry, index|
      execution.recipients.create!(
        campaign: campaign,
        contact: campaign.account.contacts.find_by(id: entry['contact_id']),
        inbox: rotation.inbox_for(index),
        name: entry['name'],
        email: entry['email'],
        destination: entry['destination'],
        phone_number: entry['phone_number'],
        source: entry['source'],
        metadata: entry['metadata']
      )
    end

    execution.update!(total_count: execution.recipients.count)
    campaign.update!(estimated_recipients: execution.total_count)
  end

  def schedule_recipients(execution)
    if execution.recipients.empty?
      execution.update!(status: 'completed', completed_at: Time.current)
      campaign.update!(status: 'completed', completed_at: Time.current)
      return
    end

    cursor = Time.current
    window = JrcCampaigns::ScheduleWindow.new(campaign)
    execution.recipients.order(:id).each do |recipient|
      cursor += random_delay.seconds
      scheduled_at = window.next_time(cursor)
      recipient.update!(scheduled_at: scheduled_at)
      JrcCampaigns::DispatchStepJob.set(wait_until: scheduled_at).perform_later(recipient.id, campaign.steps.first.id)
      cursor = scheduled_at
    end
  end

  def random_delay
    min = campaign.delay_min_seconds.to_i
    max = campaign.delay_max_seconds.to_i
    return min if max <= min

    rand(min..max)
  end
end
