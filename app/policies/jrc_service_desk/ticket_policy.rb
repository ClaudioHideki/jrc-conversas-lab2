# frozen_string_literal: true

class JrcServiceDesk::TicketPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && capability?(:tickets_view)
  end

  def show?
    record.persisted? && record_unit_visible? && capability?(:tickets_view) &&
      Scope.new(user_context, JrcServiceDesk::Ticket).resolve.exists?(id: record.id)
  end

  def create?
    return false unless record.new_record? && record_unit_allowed? && operational_context.capability?(:tickets_create)

    access = operational_context.supervision_access
    return true unless access.restricted?(record.unit_id)
    return access.grants('tickets_create').any? { |grant| grant[:unit_id] == record.unit_id } unless record.queue_id || record.team_id

    access.allowed?(record, 'tickets_create')
  end

  { update: :tickets_edit, assign: :tickets_assign, transfer: :tickets_transfer,
    change_priority: :priority_change, add_note: :notes_add, view_notes: :notes_view,
    view_history: :history_view, view_conversations: :conversations_view,
    link_conversation: :conversations_link, view_sla: :sla_view, view_customer: :customers_view }.each do |action, capability|
    define_method("#{action}?") do
      read = %i[view_notes view_history view_conversations view_sla view_customer].include?(action)
      show? && (read || record_unit_allowed?) && capability?(capability)
    end
  end

  def destroy?
    show? && record_unit_allowed? && operational_context.administrator?
  end

  def customer_publish?
    add_note? && capability?(:customer_publish)
  end

  def scoped_permission?(permission)
    operational_context.supervision_access.allowed?(record, permission)
  end

  # LifecycleActionPolicy and the pinned policy authorize individual transitions.
  def transition?
    false
  end

  protected

  def capability?(name)
    super && (record.is_a?(Class) || scoped_permission?(name))
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      resolve_for('tickets_view')
    end

    def resolve_for(permission)
      context = operational_context
      return scope.none unless context.capability?(:tickets_view)

      records = JrcServiceDesk::RecordWithdrawal.excluding(scope.where(account_id: context.account.id, unit_id: context.unit_scope.select(:id)), :ticket)
      restricted = context.supervision_access.scope(records, permission: permission)
      return restricted if context.capability?(:tickets_view_all)

      memberships = context.active_memberships.select(:id)
      permitted = records.where(created_by_membership_id: context.creator_memberships)
                         .or(records.where(assignee_membership_id: memberships))
                         .or(records.where(team_id: context.native_team_ids))
      permitted = permitted.or(approval_records(records, context, memberships)) if context.capability?(:approvals_view)
      ordinary = permitted.where.not(unit_id: context.supervision_access.restricted_units)
      supervised = restricted.where(unit_id: context.supervision_access.restricted_units)
      ordinary.or(supervised)
    end

    private

    def approval_records(records, context, memberships)
      approvals = JrcServiceDesk::TicketApproval.where(
        account_id: context.account.id, unit_id: context.unit_scope.select(:id), approver_membership_id: memberships
      ).select(:ticket_id)
      records.where(id: approvals)
    end
  end
end
