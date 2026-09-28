# frozen_string_literal: true

class JrcServiceDesk::WorkStatusPolicy < JrcServiceDesk::TicketPolicy
  def change_work_status?
    return false unless show? && capability?(:work_status_change) && record.status.phase == 'open'
    version = JrcServiceDesk::LifecycleSelector.new(record).applicable
    version && version.definition['transitions'].any? { |r| r['action'] == 'work_status' && r['from_status_ids'].include?(record.status_id) } || false
  end
end
