# frozen_string_literal: true

class JrcServiceDesk::ContactNotificationPreferences < JrcServiceDesk::BaseService
  KEY = 'service_desk_notification_channels'
  CHANNELS = %w[email whatsapp].freeze

  def self.channels(contact)
    values = contact.custom_attributes
    return CHANNELS unless values.key?(KEY)

    stored = values[KEY]
    valid?(stored) ? stored : []
  end

  def self.valid?(value)
    value.is_a?(Array) && value.uniq == value && (value - CHANNELS).empty?
  end

  def call(ticket_id:, channels:)
    raise ArgumentError, 'Explicit supported channels required' unless self.class.valid?(channels)

    with_ticket(ticket_id, :view_customer?) do |ticket|
      raise Pundit::NotAuthorizedError unless context.capability?(:notifications_manage)

      contact = ticket.requester
      JrcServiceDesk::NativeExecutionContext.with(context.to_h) { authorize!(contact, :update?) }
      persist_preferences!(ticket, contact, channels)
      channels
    end
  end

  private

  def persist_preferences!(ticket, contact, channels)
    contact.lock!
    before = self.class.channels(contact)
    contact.custom_attributes = contact.custom_attributes.merge(KEY => channels)
    contact.save!
    comment = JSON.generate('source' => 'jrc_service_desk_notification_preferences',
                            'account_id' => ticket.account_id, 'unit_id' => ticket.unit_id,
                            'ticket_id' => ticket.id, 'membership_id' => actor_membership.id)
    Audited::Audit.create!(auditable: contact, associated: ticket.unit, user: context.user, action: 'update',
                           audited_changes: { KEY => [before, channels] }, comment: comment)
  end
end
