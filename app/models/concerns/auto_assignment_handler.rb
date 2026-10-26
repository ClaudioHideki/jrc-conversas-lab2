module AutoAssignmentHandler
  extend ActiveSupport::Concern
  include Events::Types

  included do
    before_save :record_auto_assignment_request
    after_commit :run_auto_assignment
  end

  private

  def record_auto_assignment_request
    if assignee_id.present? || !open?
      self.auto_assignment_requested_at = nil
      return
    end
    return unless new_record? || will_save_change_to_status?

    self.auto_assignment_requested_at = Time.current if
      (JrcHumanAssignment::Policy.enabled_for?(account, inbox_id) || inbox.auto_assignment_v2_enabled?) &&
      AutoAssignment::Eligibility.new(inbox: inbox).configuration_reason.nil?
  end

  def run_auto_assignment
    # Assignment V2: Also trigger assignment when conversation is resolved or snoozed,
    # bypassing the open-only condition so the AssignmentJob can redistribute capacity.
    return unless conversation_status_changed_to_open? || conversation_status_changed_to_resolved_or_snoozed? || (open? && saved_change_to_team_id?)
    return unless should_run_auto_assignment?

    if inbox.auto_assignment_v2_enabled?
      # Coalesced retries only inspect requests persisted by a new open event.
      AutoAssignment::AssignmentJob.enqueue_for_inbox(inbox.id)
    else
      # Use legacy assignment system
      # If conversation has a team, only consider team members for assignment
      allowed_agent_ids = team_id.present? ? team_member_ids_with_capacity : inbox.member_ids_with_assignment_capacity
      AutoAssignment::AgentAssignmentService.new(
        conversation: self, allowed_agent_ids: allowed_agent_ids,
        replace_inaccessible_assignee: saved_change_to_status? && status_before_last_save.present? && open?
      ).perform
    end
  end

  def conversation_status_changed_to_resolved_or_snoozed?
    inbox.auto_assignment_v2_enabled? && saved_change_to_status? && (resolved? || snoozed?)
  end

  def team_member_ids_with_capacity
    return [] if team.blank? || team.allow_auto_assign.blank?

    inbox.member_ids_with_assignment_capacity & team.members.ids
  end

  def should_run_auto_assignment?
    return false if JrcHumanAssignment::Policy.enabled_for?(account, inbox_id)
    return false unless inbox.enable_auto_assignment?
    return false unless AutoAssignment::Eligibility.new(inbox: inbox).configuration_reason.nil?
    # Assignment V2: Resolved/snoozed conversations still have an assignee, so bypass the
    # assignee-blank check below. The AssignmentJob needs to run to rebalance assignments.
    return true if conversation_status_changed_to_resolved_or_snoozed?

    # run only if assignee is blank or doesn't have access to inbox
    assignee.blank? || inbox.members.exclude?(assignee)
  end
end
