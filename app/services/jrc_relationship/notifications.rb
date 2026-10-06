class JrcRelationship::Notifications
  def self.call(action, event: 'critical_action')
    return unless action.account.feature_enabled?('jrc_relationship') && action.account.active?
    action.with_lock do
      action.account.account_users.includes(:user).find_each do |member|
        policy = JrcRelationship::ModulePolicy.new({ account: action.account, user: member.user, account_user: member }, action.account)
        next unless policy.access? && (member.user_id == action.owner_id || policy.team?)
        context = JrcRelationship::Context.new(member)
        next unless context.records(JrcRelationship::Action).exists?(id: action.id)
        notification = Notification.find_or_initialize_by(account: action.account, user: member.user, primary_actor: action,
          notification_type: 'relationship_action')
        events = Array(notification.meta&.dig('relationship_events'))
        next if events.include?(event)
        notification.assign_attributes(meta: { 'relationship_event' => event, 'relationship_events' => (events + [event]).last(100) },
          read_at: nil, last_activity_at: Time.current)
        notification.save!
      end
    end
  end

  def self.visible?(notification)
    member = notification.account.account_users.find_by(user_id: notification.user_id)
    return false unless member && notification.account.feature_enabled?('jrc_relationship')
    policy = JrcRelationship::ModulePolicy.new({ account: notification.account, user: member.user, account_user: member }, notification.account)
    policy.access? && JrcRelationship::Context.new(member).records(JrcRelationship::Action).exists?(id: notification.primary_actor_id)
  end
end
