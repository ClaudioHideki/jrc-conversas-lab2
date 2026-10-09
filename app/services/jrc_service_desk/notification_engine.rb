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

    @source.channels.filter_map { |channel| create_delivery(channel) }
  end

  def self.channel(inbox)
    return 'email' if inbox.channel_type == 'Channel::Email'
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

  def create_delivery(channel)
    JrcServiceDesk::Base.transaction do
      @record.ticket.unit.lock!
      origin = @source.origin_attributes
      existing = JrcServiceDesk::NotificationDelivery.find_by(origin.merge(channel: channel, attempt_number: 1))
      next existing if existing

      policy = self.class.current_policy(@record, channel)
      next if !@source.note? && policy.nil?

      row = build_delivery(channel, policy)
      apply_eligibility(row) if policy&.enabled?
      row.save!
      row
    end
  end

  def build_delivery(channel, policy)
    snapshot = @source.snapshot
    JrcServiceDesk::NotificationDelivery.new(
      @source.origin_attributes.merge(account: @record.account, unit: @record.unit, ticket: @record.ticket,
                                      notification_policy_version: policy,
                                      execution_membership: @source.note? ? @source.author : policy.published_by_membership,
                                      conversation: @source.conversation(policy, channel), channel: channel,
                                      state: 'blocked', reason: 'policy_disabled',
                                      source_snapshot: snapshot, source_digest: JrcServiceDesk::CanonicalJson.digest(snapshot))
    )
  end

  def apply_eligibility(row)
    reason = self.class.blocker(row)
    row.assign_attributes(state: reason ? 'blocked' : 'queued', reason: reason,
                          recipient: reason ? nil : self.class.recipient(row.conversation, row.channel))
  end
end
