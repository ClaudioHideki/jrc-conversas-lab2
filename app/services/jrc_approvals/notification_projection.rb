# Immutable audit events feed a transactional outbox. Projection never runs inside a domain decision transaction.
class JrcApprovals::NotificationProjection
  def initialize(event_id)
    @event = JrcApprovals::AuditEvent.find(event_id)
    @account = @event.account
    @outbox = JrcApprovals::NotificationOutbox.find_by!(account_id: @account.id, source_event_id: @event.id)
  end

  def call
    return unless JrcApprovals::Notifications::EVENTS.include?(@event.event_type)
    return unless @account.active? && @account.feature_enabled?('jrc_approvals')
    return if completed?

    project_recipients!(*target)
    complete!
  end

  private

  def project_recipients!(actor, recipients)
    return unless actor

    recipients.uniq(&:id).each { |member| project!(actor, member) }
  end

  def complete!
    @outbox.with_lock do
      next if completed?

      JrcApprovals::Ledger.audit!(account: @account, actor: @event.actor, event: 'notification_projection_complete',
                                  key: completion_key, data: { source_event_id: @event.id, system_projection: true })
      @outbox.update!(completed_at: Time.current)
    end
  end

  def completion_key
    "approval_notification:#{@event.id}:complete"
  end

  def completed?
    @outbox.completed_at.present?
  end

  def target
    if JrcApprovals::Notifications::REQUEST_EVENTS.include?(@event.event_type)
      request_target
    else
      delegation_target
    end
  end

  def request_target
    id = @event.event_type == 'request_adjusted' ? @event.data.fetch('revised_request_id') : @event.request_id
    record = JrcApprovals::Request.where(account_id: @account.id).find(id)
    recipients = []
    recipients << record.requester unless %w[request_created request_revised].include?(@event.event_type)
    if record.state == 'pending'
      recipients.concat(@account.account_users.includes(:user).select do |member|
        JrcApprovals::DecisionOptions.call(account: @account, user: member.user, record: record).any?
      end)
    end
    [record, recipients]
  end

  def delegation_target
    own = @event.event_type.start_with?('own_')
    grant = delegation_grant(own)
    return [nil, []] if !own && JrcApprovals::OwnDelegationBindings.own_id(grant)
    return [nil, []] unless grant_deliverable?(grant, own)

    actor = own ? grant.record : JrcApprovals::AuditEvent.find_by!(account_id: @account.id, correlation_key: "delegation:#{grant.id}:grant")
    ids = @event.event_type.end_with?('_granted') ? [grant.delegate_id] : [grant.principal_id, grant.delegate_id]
    [actor, @account.account_users.includes(:user).where(id: ids).to_a]
  end

  def delegation_grant(own)
    return JrcApprovals::Delegation.where(account_id: @account.id).find(@event.data.fetch('delegation_id')) unless own

    id = @event.event_type == 'own_delegation_granted' ? @event.id : @event.data.fetch('grant_id')
    JrcApprovals::OwnDelegations.find!(@account, id)
  end

  def grant_deliverable?(grant, own)
    return true unless @event.event_type.end_with?('_granted')

    revoked = own ? grant.revoked? : grant.revoked_at.present?
    !revoked && grant.ends_at > Time.current
  end

  def project!(actor, member)
    return unless JrcApprovals::Notifications.actor_visible?(account: @account, user: member.user, actor: actor)

    written = false
    notice = Notification.transaction do
      JrcApprovals::Ledger.lock!(@account.id, "approval_notice:#{actor.class.name}:#{actor.id}:#{member.id}")
      row = Notification.find_or_initialize_by(account: @account, user: member.user, primary_actor: actor, notification_type: 'approval_event')
      written = write_notice!(row)
      row
    end
    # Retry failed post-commit delivery without recreating the row or resetting its read mark.
    return unless !written && notice.meta['source_event_id'] == @event.id

    Rails.configuration.dispatcher.dispatch(Events::Types::NOTIFICATION_UPDATED, Time.current, notification: notice)
  end

  def write_notice!(row)
    return false unless row.new_record? || row.meta.fetch('source_event_id', 0) < @event.id

    row.assign_attributes(meta: { 'source_event_id' => @event.id, 'approval_event' => @event.event_type },
                          read_at: nil, last_activity_at: Time.current)
    row.save!
    true
  end
end
