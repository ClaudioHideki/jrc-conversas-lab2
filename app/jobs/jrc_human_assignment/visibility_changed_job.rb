class JrcHumanAssignment::VisibilityChangedJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    event = JrcHumanAssignmentPolicyEvent.find_by(id: event_id)
    return unless event&.inbox && event.account.active?

    users = (event.inbox.members.pluck(:id) + event.account.administrators.pluck(:id)).uniq
    Conversations::UnreadCounts::FilteredCountInvalidator.new(event.account).users_visibility_changed!(user_ids: users)
    tokens = User.where(id: users).pluck(:pubsub_token)
    ActionCableBroadcastJob.perform_later(tokens, 'conversation.access_reset', { account_id: event.account_id })
  end
end
