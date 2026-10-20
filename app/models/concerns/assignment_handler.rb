module AssignmentHandler
  extend ActiveSupport::Concern
  include Events::Types

  included do
    before_save :ensure_assignee_is_from_team
    after_commit :notify_assignment_change, :process_assignment_changes
    after_commit :schedule_human_distribution
  end

  private

  def ensure_assignee_is_from_team
    return unless team_id_changed?

    validate_current_assignee_team
    self.assignee ||= find_assignee_from_team
  end

  def validate_current_assignee_team
    self.assignee_id = nil if team&.members&.exclude?(assignee)
  end

  def find_assignee_from_team
    return if team&.allow_auto_assign.blank?
    return if JrcHumanAssignment::Policy.enabled_for?(account, inbox_id)

    team_members_with_capacity = inbox.member_ids_with_assignment_capacity & team.members.ids
    ::AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: team_members_with_capacity).find_assignee
  end

  def schedule_human_distribution
    return unless JrcHumanAssignment::Policy.enabled_for?(account, inbox_id)
    return unless previous_changes.keys.intersect?(%w[id team_id status assignee_id assignee_agent_bot_id])
    return if assignee_id.present? && !saved_change_to_status?

    JrcHumanAssignment::DispatchJob.perform_later(account_id)
  end

  def notify_assignment_change
    {
      ASSIGNEE_CHANGED => -> { saved_change_to_assignee_id? },
      TEAM_CHANGED => -> { saved_change_to_team_id? }
    }.each do |event, condition|
      condition.call && dispatcher_dispatch(event, previous_changes)
    end
  end

  def process_assignment_changes
    process_assignment_activities
  end

  def process_assignment_activities
    user_name = Current.user.name if Current.user.present?
    if saved_change_to_team_id?
      create_team_change_activity(user_name)
    elsif saved_change_to_assignee_id?
      create_assignee_change_activity(user_name)
    end
  end

  def self_assign?(assignee_id)
    assignee_id.present? && Current.user&.id == assignee_id
  end
end
