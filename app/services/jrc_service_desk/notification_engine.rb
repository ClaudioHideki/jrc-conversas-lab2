# frozen_string_literal: true

class JrcServiceDesk::NotificationEngine
  def initialize(record)
    @record = record
    @source = JrcServiceDesk::NotificationSource.new(record)
  end

  def call
    return [] unless @source.publishable?
    return [] unless @source.note? || JrcServiceDesk::NotificationEvent.active?(@record)
    return [] unless @source.note? || @record.data['notification_fields'].is_a?(Hash)

    results = []
    selected = {}
    policies = @source.channels.filter_map { |channel| self.class.current_policy(@record, channel) }
    ordered = policies.sort_by { |policy| policy.settings.fetch('channel_order', @source.channels).index(policy.channel) || 99 }
    ordered.each do |policy|
      controls = JrcServiceDesk::NotificationControls.new(policy.settings)
      matched = controls.match?(@source)

      controls.recipient_ids(@record.ticket).each do |contact_id|
        next if policy.settings['multichannel_mode'] == 'first_available' && selected[contact_id]

        row = create_delivery(policy.channel, contact_id: contact_id, blocked_reason: matched ? nil : 'conditions_not_matched')
        results << row if row
        selected[contact_id] = true if row && row.state != 'blocked'
      end
    end
    # Notes with no policy retain their native explicit blocked receipt.
    @source.channels.each { |channel| results << create_delivery(channel) } if policies.empty? && @source.note?
    results.compact
  end

  def self.channel(inbox)
    return 'email' if inbox.channel_type == 'Channel::Email'
    return 'whatsapp' if JrcBroker::OutboundChannel.available?(inbox)
    return 'whatsapp' if inbox.channel_type == 'Channel::Whatsapp' || (inbox.channel_type == 'Channel::TwilioSms' && inbox.twilio_whatsapp?)

    nil
  end

  def self.recipient(conversation, channel)
    channel == 'email' ? conversation.contact.email : conversation.contact.phone_number
  end

  def self.current_policy(record, channel)
    JrcServiceDesk::NotificationPolicySelector.call(record, channel)
  end

  def self.blocker(row)
    JrcServiceDesk::NotificationEligibility.new(row).blocker
  end

  private

  def create_delivery(channel, contact_id: @record.ticket.requester_id, blocked_reason: nil)
    JrcServiceDesk::Base.transaction do
      @record.ticket.unit.lock!
      origin = @source.origin_attributes
      existing = JrcServiceDesk::NotificationDelivery.where(origin.merge(channel: channel,
                                                                         attempt_number: 1)).where(recipient_contact_id: if contact_id == @record.ticket.requester_id
                                                                                                                           [
                                                                                                                             nil, contact_id
                                                                                                                           ]
                                                                                                                         else
                                                                                                                           contact_id
                                                                                                                         end).first
      next existing if existing

      policy = self.class.current_policy(@record, channel)
      next if !@source.note? && policy.nil?

      row = build_delivery(channel, policy, contact_id)
      if blocked_reason
        row.reason = blocked_reason
      elsif policy&.enabled?
        apply_eligibility(row)
      end
      if row.recipient.present?
        same_destination = JrcServiceDesk::NotificationDelivery.find_by(origin.merge(channel: channel, attempt_number: 1, recipient: row.recipient))
        next same_destination if same_destination
      end
      row.save!
      row
    end
  end

  def build_delivery(channel, policy, contact_id)
    snapshot = @source.snapshot
    JrcServiceDesk::NotificationDelivery.new(
      @source.origin_attributes.merge(account: @record.account, unit: @record.unit, ticket: @record.ticket,
                                      notification_policy_version: policy,
                                      execution_membership: @source.note? ? @source.author : policy.published_by_membership,
                                      conversation: @source.conversation(policy, channel, contact_id: contact_id), channel: channel,
                                      recipient_contact_id: contact_id,
                                      state: 'blocked', reason: 'policy_disabled',
                                      source_snapshot: snapshot, source_digest: JrcServiceDesk::CanonicalJson.digest(snapshot))
    )
  end

  def apply_eligibility(row)
    controls = JrcServiceDesk::NotificationControls.new(row.notification_policy_version.settings)
    row.not_before = controls.next_time
    reason = row.not_before > 1.second.from_now && controls.settings['outside_window'] == 'skip' ? 'outside_window' : self.class.blocker(row)
    row.assign_attributes(state: reason ? 'blocked' : 'queued', reason: reason,
                          recipient: reason ? nil : self.class.recipient(row.conversation, row.channel))
  end
end
