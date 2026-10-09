# frozen_string_literal: true

class JrcServiceDesk::PublicationPlan
  def initialize(ticket:, context:)
    @ticket = ticket
    @context = context
    @projection = JrcServiceDesk::ComposerProjection.new(ticket: ticket, context: context)
  end

  def call(attributes, files)
    values = JrcServiceDesk::Input.attributes(attributes, JrcServiceDesk::AddNoteService::FIELDS)
    audience = JrcServiceDesk::InteractionVisibility.attributes(values)
    JrcServiceDesk::InteractionVisibility.authorize_publication!(@context, @ticket, **audience)
    validate_body!(values['body'])
    validate_previous!(values)
    content_plan(values, audience, files)
  end

  private

  def content_plan(values, audience, files)
    destinations = destinations(values, audience)
    details = @projection.call
    authorize_recipient!(audience, details)
    content = values.slice('body', 'previous_note_id', 'publication_reason').symbolize_keys
    deliveries = audience[:notification_channels].map { |channel| delivery_plan(channel, destinations.fetch(channel), values['body']) }
    scope.merge(content, audience: audience[:visibility], audience_team_id: audience[:audience_team_id],
                         recipient: details[:recipient], files: files, deliveries: deliveries)
  end

  def scope
    { account_id: @ticket.account_id.to_s, unit_id: @ticket.unit_id.to_s, ticket_id: @ticket.id.to_s,
      ticket_revision: @ticket.lock_version, requester_id: @ticket.requester_id.to_s, company_id: @ticket.company_id&.to_s,
      capabilities: @context.effective_capabilities.sort }
  end

  def validate_body!(body)
    raise ArgumentError, 'Explicit body required' unless body.is_a?(String) && body.strip.present? && body.length <= 50_000
  end

  def validate_previous!(values)
    return unless values['previous_note_id']

    previous = @ticket.ticket_notes.find(JrcServiceDesk::Input.id(values['previous_note_id']))
    Pundit.authorize(@context.to_h, previous, :show?)
    reason = values['publication_reason']
    raise ArgumentError, 'Explicit publication reason required' unless reason.is_a?(String) && reason.strip.present? && reason.length <= 2000
  end

  def destinations(values, audience)
    rows = values.fetch('notification_conversations', {})
    raise ArgumentError, 'Explicit destinations required' unless rows.is_a?(Hash) && rows.keys.sort == audience[:notification_channels].sort

    rows
  end

  def authorize_recipient!(audience, details)
    raise Pundit::NotAuthorizedError if JrcServiceDesk::InteractionVisibility::PUBLIC.include?(audience[:visibility]) && details[:recipient].nil?
  end

  def delivery_plan(channel, conversation_id, body)
    link = @ticket.ticket_conversations.find_by!(conversation_id: JrcServiceDesk::Input.id(conversation_id))
    Pundit.authorize(@context.to_h, link, :show?)
    row = @projection.delivery(channel, link.conversation)
    { channel: channel, conversation_id: link.conversation_id.to_s,
      recipient: JrcServiceDesk::NotificationEngine.recipient(link.conversation, channel).to_s,
      reason: JrcServiceDesk::NotificationEngine.blocker(row) }.merge(delivery_content(row, body))
  end

  def delivery_content(row, body)
    policy = row.notification_policy_version
    fields = JrcServiceDesk::NotificationSource.new(row.ticket_note).fields.merge('body' => body)
    { policy_version_id: policy&.id&.to_s, policy_digest: policy&.digest, template_version: policy&.template_version,
      content: policy ? JrcServiceDesk::NotificationSource.render(policy.template, fields) : nil }
  end
end
