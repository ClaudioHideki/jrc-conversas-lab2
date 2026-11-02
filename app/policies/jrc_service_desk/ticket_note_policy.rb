# frozen_string_literal: true

class JrcServiceDesk::TicketNotePolicy < JrcServiceDesk::TicketRecordPolicy
  def create?
    record_unit_allowed? && parent_policy.add_note? &&
      (record.visibility == 'internal' ||
       (JrcServiceDesk::InteractionVisibility::PUBLIC.include?(record.visibility) && capability?(:customer_publish)) ||
       (record.visibility == 'technical_team' && JrcServiceDesk::InteractionVisibility.readable?(record, operational_context)))
  end

  def show?
    super && JrcServiceDesk::InteractionVisibility.readable?(record, operational_context) &&
      !JrcServiceDesk::RecordWithdrawal.withdrawn?(record, :note)
  end

  def update?
    destroy? && %w[internal technical_team].include?(record.visibility)
  end

  def destroy?
    show? && parent_policy.add_note? &&
      (operational_context.administrator? || record.author_membership.account_user_id == operational_context.account_user.id)
  end

  class Scope < JrcServiceDesk::TicketRecordPolicy::Scope
    def resolve
      JrcServiceDesk::RecordWithdrawal.excluding(JrcServiceDesk::InteractionVisibility.scope(super, operational_context), :note)
    end
  end
end
