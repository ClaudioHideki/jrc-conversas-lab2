# Known pre-provider blocks must resolve visibly instead of consuming every wakeup.
class JrcCampaigns::BrokerPreCallbackBlock
  def initialize(delivery:, message:)
    @delivery = delivery
    @message = message
    @recipient = delivery.recipient
    @campaign = recipient.campaign
  end

  def perform
    delivery.with_lock do
      message.with_lock do
        next false unless JrcCampaigns::BrokerCallbackDeferral.pending?(delivery)

        if delivery.step.only_if_no_reply? && recipient.reload.replied_at.present?
          skip_replied_follow_up
        else
          pause_blocked_send
        end
        true
      end
    end
  end

  private

  attr_reader :delivery, :message, :recipient, :campaign

  def skip_replied_follow_up
    marker = delivery.metadata.fetch(JrcCampaigns::BrokerCallbackDeferral::KEY).merge('reason' => 'skipped')
    delivery.update!(status: 'skipped', error_message: 'Contato respondeu antes do envio da continuação.',
                     metadata: delivery.metadata.merge(JrcCampaigns::BrokerCallbackDeferral::KEY => marker))
    JrcCampaigns::EventLogger.call(campaign: campaign, execution: recipient.execution, recipient: recipient, event_type: 'message_skipped',
                                   payload: { step_id: delivery.step_id, message_id: message.id, reason: 'REPLIED_BEFORE_CALLBACK' })
    JrcCampaigns::ExecutionCompletionService.new(recipient.execution).check!
  end

  def pause_blocked_send
    reason = 'Envio ainda não iniciado; revise a aprovação e a configuração do remetente antes de retomar.'
    marker = delivery.metadata.fetch(JrcCampaigns::BrokerCallbackDeferral::KEY).merge('reason' => 'blocked')
    delivery.update!(error_message: reason, metadata: delivery.metadata.merge(JrcCampaigns::BrokerCallbackDeferral::KEY => marker))
    recipient.update!(error_message: reason, metadata: recipient.metadata.to_h.merge('pending_step_id' => delivery.step_id))
    JrcCampaigns::Campaign.where(id: campaign.id, account_id: campaign.account_id, status: 'running')
                          .update_all(status: 'paused', paused_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end
