class JrcCampaigns::EvolutionMessageRecorder
  def self.call(account:, inbox:, phone_number:, external_id:, kind:, body:, attributes:, media_url: nil)
    # Evolution may have already mirrored the direct API send into this inbox.
    message = account.messages.find_by(inbox_id: inbox.id, source_id: "WAID:#{external_id}")
    return message if message

    contact = account.contacts.find_by(phone_number: phone_number) || account.contacts.create!(phone_number: phone_number)
    link = contact.contact_inboxes.find_or_create_by!(inbox: inbox) { |record| record.source_id = "#{phone_number.delete_prefix('+')}@s.whatsapp.net" }
    conversation = contact.conversations.where(inbox: inbox, contact_inbox: link).order(created_at: :desc).first
    conversation ||= account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: link, status: 'pending')
    message = conversation.messages.build(
      account: account, inbox: inbox, message_type: 'outgoing', content: body, source_id: "WAID:#{external_id}",
      additional_attributes: attributes.merge('jrc_campaign_evolution' => true)
    )
    if kind.in?(%w[image document video audio])
      message.attachments.build(account: account, file_type: { 'image' => 'image', 'video' => 'video' }.fetch(kind, 'file'), external_url: media_url)
    end
    message.save!
    message
  end
end
