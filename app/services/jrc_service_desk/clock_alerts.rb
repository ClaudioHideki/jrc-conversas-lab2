# frozen_string_literal: true

module JrcServiceDesk::ClockAlerts
  module_function

  def schedule(event, threshold)
    Array(threshold['notification_member_ids']).each do |member_id|
      Array(threshold['notification_channels']).each do |channel|
        JrcServiceDesk::ClockAlertDelivery.find_or_create_by!(ticket_event: event, recipient_account_user_id: member_id, channel: channel) do |row|
          row.assign_attributes(account: event.account, unit: event.unit, ticket: event.ticket)
        end
      end
    end
  end

  def context_for(account, member)
    JrcServiceDesk::OperationalContext.new(account: account, user: member.user, account_user: member)
  end

  def visible?(notification)
    member = notification.account.account_users.find_by(user_id: notification.user_id)
    return false unless member

    ctx = context_for(notification.account, member)
    ticket = JrcServiceDesk::Ticket.find_by(account_id: notification.account_id, id: notification.primary_actor_id)
    return false unless ticket

    JrcServiceDesk::TicketPolicy.new(ctx.to_h, ticket).view_sla?
  end

  def blocker(row)
    event = row.ticket_event
    clock = JrcServiceDesk::OlaClock.find_by(account_id: row.account_id, unit_id: row.unit_id, ticket_id: row.ticket_id, id: event.data['clock_id'])
    return 'clock_missing' unless clock && event.event_type == 'clock_threshold_reached'

    queue = clock.queue.reload
    revision = if clock.queue_policy_version
                 queue.current_policy_version&.digest
               else
                 JrcServiceDesk::OlaTracker.current_revision(queue,
                                                             clock.sla_snapshot)
               end
    return 'publication_changed' unless queue.active? && revision == event.data['policy_digest'] && clock.policy_revision == revision

    threshold = JrcServiceDesk::ClockEscalationPolicy.new(clock.escalation_snapshot).thresholds.find do |item|
      item['percent'] == event.data['percent']
    end
    unless threshold && Array(threshold['notification_member_ids']).include?(row.recipient_account_user_id) && Array(threshold['notification_channels']).include?(row.channel)
      return 'recipient_changed'
    end

    actor_member = event.actor_membership.account_user
    actor = context_for(row.account, actor_member)
    actor_policy = JrcServiceDesk::TicketPolicy.new(actor.to_h, row.ticket)
    return 'authority_revoked' unless actor_policy.update? && actor_policy.view_sla?

    member = AccountUser.find_by(account_id: row.account_id, id: row.recipient_account_user_id)
    return 'recipient_revoked' unless member

    recipient = context_for(row.account, member)
    return 'recipient_revoked' unless JrcServiceDesk::TicketPolicy.new(recipient.to_h, row.ticket).view_sla?
    return if row.channel == 'in_app'
    return 'smtp_unavailable' unless ENV['SMTP_ADDRESS'].present?
    return 'recipient_unconfirmed' unless member.user.confirmed_at

    setting = member.user.notification_settings.find_by(account_id: row.account_id)
    'recipient_preference' unless setting&.email_service_desk_clock?
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ArgumentError
    'authority_revoked'
  end
end
