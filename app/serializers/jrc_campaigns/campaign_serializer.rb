class JrcCampaigns::CampaignSerializer
  def initialize(campaign)
    @campaign = campaign
  end

  def as_json
    campaign.as_json(only: scalar_fields).merge(
      campaign_inboxes: campaign.campaign_inboxes.sort_by(&:position).map { |link| inbox_json(link) },
      steps: campaign.steps.map { |step| step_json(step) },
      approval_valid: approval_valid?,
      latest_execution: execution_json(campaign.latest_execution)
    )
  end

  private

  attr_reader :campaign

  def approval_valid?
    campaign.approval_valid?
  rescue JrcBroker::Client::Error
    # A failed remote read cannot approve a send or turn an already persisted pause into an API error.
    false
  end

  def scalar_fields
    [:id, :name, :status, :trigger_type, :scheduled_at, :audience_type, :audience_config, :message_body, :inbox_id,
     :rotation_mode, :delay_min_seconds, :delay_max_seconds, :sending_window, :conversation_mode, :recurrence_config, :follow_up_config,
     :estimated_recipients, :sent_count, :failed_count, :delivered_count, :read_count, :replied_count, :clicked_count, :started_at,
     :paused_at, :completed_at, :last_execution_at, :last_error, :created_at, :updated_at,
     :review_digest, :approved_by_id, :approved_at, :approval_expires_at]
  end

  def inbox_json(link)
    {
      id: link.id,
      inbox_id: link.inbox_id,
      name: link.inbox.name,
      weight: link.weight,
      position: link.position,
      enabled: link.enabled
    }
  end

  def step_json(step)
    step.as_json(only: [:id, :position, :kind, :body, :media_url, :file_name, :template_name, :template_namespace, :template_language,
                        :template_params, :inbox_overrides, :delay_after_seconds, :only_if_no_reply, :follow_up_after_hours])
  end

  def execution_json(execution)
    return unless execution

    execution.as_json(only: [:id, :run_number, :status, :total_count, :sent_count, :failed_count, :delivered_count, :read_count, :replied_count,
                              :started_at, :completed_at])
  end
end
