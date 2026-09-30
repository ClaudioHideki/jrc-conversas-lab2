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
    record.new_record? && record_unit_allowed? && capability?(:tickets_create)
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

  # LifecycleActionPolicy and the pinned policy authorize individual transitions.
  def transition?
    false
  end

  class Scope < JrcServiceDesk::OperationalPolicy::Scope
    def resolve
      context = operational_context
      return scope.none unless context.capability?(:tickets_view)

      records = scope.where(account_id: context.account.id, unit_id: context.unit_scope.select(:id))
      return records if context.capability?(:tickets_view_all) # Always within the current Account and authorized view scope.

      memberships = context.active_memberships.select(:id)
      records.where(created_by_membership_id: memberships)
        .or(records.where(assignee_membership_id: memberships))
        .or(records.where(team_id: context.native_team_ids))
    end
  end
end
