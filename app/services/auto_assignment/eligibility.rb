class AutoAssignment::Eligibility
  pattr_initialize [:inbox!, :conversation]

  def configuration_reason
    return 'account_inactive' unless inbox.account.active?
    return nil if JrcHumanAssignment::Policy.enabled_for?(inbox.account, inbox.id)
    return 'auto_assignment_disabled' unless inbox.enable_auto_assignment?
    return nil unless inbox.auto_assignment_v2_enabled?

    policy = inbox.assignment_policy
    return 'policy_missing' unless policy && policy.account_id == inbox.account_id
    return 'policy_disabled' unless policy.enabled?

    nil
  end

  def conversation_reason(allow_inaccessible_assignee: false)
    return nil unless conversation
    return 'conversation_not_eligible' unless conversation.account_id == inbox.account_id && conversation.inbox_id == inbox.id && conversation.open?
    replacement = allow_inaccessible_assignee && conversation.assignee_id.present? &&
                  !inbox.inbox_members.exists?(user_id: conversation.assignee_id)
    return 'conversation_already_assigned' if conversation.assignee_agent_bot_id.present? || (conversation.assignee_id.present? && !replacement)
    return 'nico_control_active' if conversation.custom_attributes['nico_control'] == 'active' ||
                                   JrcFlowRun.live.exists?(account_id: inbox.account_id, conversation_id: conversation.id)
    if conversation.team_id.present?
      team = conversation.team
      return 'team_restriction' unless team&.account_id == inbox.account_id && team.allow_auto_assign?
    end
    return 'team_restriction' if JrcHumanAssignment::Policy.enabled_for?(inbox.account, inbox.id) && conversation.team_id.nil?

    nil
  end

  def agent_reason(account_user, online_ids: nil)
    return 'account_membership_missing' unless account_user&.account_id == inbox.account_id
    return 'agent_auto_assignment_disabled' unless account_user.auto_assignment_enabled?
    return 'agent_unavailable' unless account_user.online?

    ids = online_ids || OnlineStatusTracker.effective_available_users(inbox.account_id).keys.map(&:to_i)
    return 'no_online_agents' unless ids.include?(account_user.user_id)
    return 'inbox_restriction' unless inbox.inbox_members.exists?(user_id: account_user.user_id)
    return 'team_restriction' if conversation&.team_id.present? && !conversation.team&.members&.exists?(id: account_user.user_id)
    if inbox.account.feature_enabled?('jrc_contact_center') &&
       JrcContactCenter::Qualification.pending.where(account_id: inbox.account_id, account_user_id: account_user.id).exists?
      return 'qualification_pending'
    end
    return 'capacity_reached' unless inbox.member_ids_with_assignment_capacity.include?(account_user.user_id)

    nil
  end
end
