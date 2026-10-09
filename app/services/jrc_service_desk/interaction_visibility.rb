# frozen_string_literal: true

# One audience contract for interactions, tasks, attachments, timeline and AI projections.
# A native operator context is mandatory. Customer identity is a separate portal concern.
module JrcServiceDesk::InteractionVisibility
  VALUES = %w[internal technical_team customer public_without_notification].freeze
  PUBLIC = %w[customer public_without_notification].freeze

  def self.attributes(values)
    visibility = values.fetch('visibility', 'internal')
    raise ArgumentError, 'Unknown interaction visibility' unless VALUES.include?(visibility)

    team_id = audience(values, visibility)
    channels = channels(values, visibility)
    { visibility: visibility, audience_team_id: team_id, notification_channels: channels,
      notification_state: channels.any? ? 'blocked_activation' : 'not_requested' }
  end

  def self.audience(values, visibility)
    team_id = values['audience_team_id'] && JrcServiceDesk::Input.id(values['audience_team_id'])
    raise ArgumentError, 'Technical audience requires an explicit team' if (visibility == 'technical_team') != !team_id.nil?

    team_id
  end
  private_class_method :audience

  def self.channels(values, visibility)
    channels = values.fetch('notification_channels', [])
    unless channels.is_a?(Array) && channels.uniq == channels && (channels - %w[email whatsapp]).empty?
      raise ArgumentError, 'Unsupported notification channels'
    end
    raise ArgumentError, 'Only customer interactions may request external delivery' if visibility != 'customer' && channels.any?

    channels
  end
  private_class_method :channels

  def self.authorize_publication!(context, ticket, visibility:, audience_team_id:, **options)
    capability = options.fetch(:capability, :notes_add)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::TicketPolicy.new(context.to_h, ticket).show? &&
                                            context.unit_allowed?(ticket.unit) && context.capability?(capability)

    if PUBLIC.include?(visibility)
      raise Pundit::NotAuthorizedError unless context.capability?(:customer_publish)
    elsif visibility == 'technical_team'
      authorize_technical!(context, ticket, audience_team_id)
    end
  end

  def self.authorize_technical!(context, ticket, audience_team_id)
    team = Team.where(account_id: context.account.id).find(audience_team_id)
    allowed = ticket.team_id == team.id && context.native_team_ids.exists?(id: team.id) && context.capability?(:technical_notes)
    raise Pundit::NotAuthorizedError unless allowed
  end
  private_class_method :authorize_technical!

  def self.scope(relation, context)
    public_and_internal = relation.where(visibility: VALUES - ['technical_team'])
    technical = relation.where(visibility: 'technical_team', audience_team_id: context.native_team_ids)
    context.capability?(:technical_notes) ? public_and_internal.or(technical) : public_and_internal
  end

  def self.readable?(record, context)
    return true unless record.visibility == 'technical_team'

    context.capability?(:technical_notes) && context.native_team_ids.exists?(id: record.audience_team_id)
  end

  def self.portal_scope(relation)
    relation.where(visibility: PUBLIC)
  end
end
