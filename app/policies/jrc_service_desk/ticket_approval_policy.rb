# frozen_string_literal: true

class JrcServiceDesk::TicketApprovalPolicy < JrcServiceDesk::TicketRecordPolicy
  def show?
    record_unit_allowed? && parent_policy.show? && capability?(:approvals_view)
  end

  def create?
    show? && capability?(:approvals_request)
  end

  def decide?
    show? && capability?(:approvals_decide) && target_matches?
  end

  def escalate?
    show? && capability?(:approvals_request) && record.status == 'pending'
  end

  private

  def target_matches?
    context = operational_context
    member = context.account_user
    return record.approver_membership.account_user_id == member.id if record.approver_membership
    return context.native_team_ids.exists?(id: record.approver_team_id) if record.approver_team_id
    return member.custom_role_id == record.approver_custom_role_id if record.approver_custom_role_id

    record.approver_role == member.role && member.custom_role_id.nil?
  end
end
