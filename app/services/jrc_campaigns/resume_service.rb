class JrcCampaigns::ResumeService
  def initialize(campaign)
    @campaign = campaign
  end

  def perform
    execution = campaign.latest_execution
    return unless execution&.running?

    execution.recipients.find_each do |recipient|
      step_id = recipient.metadata.to_h['pending_step_id']
      next if step_id.blank?

      step = campaign.steps.find_by(id: step_id)
      next unless step

      JrcCampaigns::BrokerRecoveryResume.new(recipient: recipient, step: step).perform
      recipient.update!(metadata: recipient.metadata.to_h.except('pending_step_id'))
      JrcCampaigns::DispatchStepJob.perform_later(recipient.id, step.id)
    end
  end

  private

  attr_reader :campaign
end
