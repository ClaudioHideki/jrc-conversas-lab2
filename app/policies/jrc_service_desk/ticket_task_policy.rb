# frozen_string_literal: true

class JrcServiceDesk::TicketTaskPolicy < JrcServiceDesk::TicketRecordPolicy
  def show?
    record_unit_allowed? && parent_policy.show? && capability?(:tasks_view) &&
      !JrcServiceDesk::RecordWithdrawal.withdrawn?(record, :task) &&
      JrcServiceDesk::InteractionVisibility.readable?(record, operational_context)
  end

  def create?
    record_unit_allowed? && parent_policy.show? && capability?(:tasks_manage)
  end

  def update?
    show? && capability?(:tasks_manage)
  end

  def destroy?
    update?
  end

  class Scope < JrcServiceDesk::TicketRecordPolicy::Scope
    def resolve
      JrcServiceDesk::RecordWithdrawal.excluding(JrcServiceDesk::InteractionVisibility.scope(super, operational_context), :task)
    end
  end
end
