class JrcCampaigns::ReplyTrackerService
  def self.call(contact:, inbox:, conversation:)
    scope = JrcCampaigns::Recipient.where(inbox: inbox)
                                   .where.not(sent_at: nil)
                                   .where(replied_at: nil)
    recipient = matching_recipient(scope, contact)
    return false unless recipient

    recipient.update!(
      status: 'replied',
      replied_at: Time.current,
      conversation: conversation,
      contact: recipient.contact || contact
    )
    recipient.execution.refresh_counters!
    recipient.campaign.refresh_counters!
    apply_on_reply_actions(recipient)
    JrcCampaigns::EventLogger.call(
      campaign: recipient.campaign,
      execution: recipient.execution,
      recipient: recipient,
      event_type: 'reply_received',
      payload: { conversation_id: conversation.id }
    )
    true
  end

  def self.matching_recipient(scope, contact)
    by_contact = scope.where(contact: contact)
    normalized_phone = JrcCampaigns::PhoneNormalizer.call(contact&.phone_number)
    normalized_email = JrcCampaigns::EmailNormalizer.call(contact&.email)
    by_destination = scope.none
    by_destination = by_destination.or(scope.where(phone_number: normalized_phone)) if normalized_phone.present?
    by_destination = by_destination.or(scope.where(email: normalized_email)) if normalized_email.present?
    return by_contact.order(sent_at: :desc).first if normalized_phone.blank? && normalized_email.blank?

    by_contact.or(by_destination).order(sent_at: :desc).first
  end
  private_class_method :matching_recipient

  def self.apply_on_reply_actions(recipient)
    config = recipient.campaign.follow_up_config.with_indifferent_access
    contact = recipient.contact
    return unless contact

    if config[:on_reply_label_id].present?
      label = recipient.campaign.account.labels.find_by(id: config[:on_reply_label_id])
      contact.add_labels(label.title) if label
    end

    return if config[:on_reply_stage_id].blank?

    stage = recipient.campaign.account.jrc_crm_stages.find_by(id: config[:on_reply_stage_id])
    return unless stage

    source_stage_ids = Array(recipient.campaign.audience_config['stage_ids']).map(&:to_i)
    deals = recipient.campaign.account.jrc_crm_deals.where(status: 'open')
    deals = deals.where(stage_id: source_stage_ids) if source_stage_ids.any?
    deals = deals.where(id: JrcCrm::DealContact.where(contact_id: contact.id).select(:deal_id)).or(deals.where(contact_id: contact.id))
    deals.find_each do |deal|
      JrcCrm::DealPipelineService.new(deal: deal, stage: stage, actor: nil).call
    end
  end
  private_class_method :apply_on_reply_actions
end
