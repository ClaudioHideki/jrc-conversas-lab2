# frozen_string_literal: true

class JrcServiceDesk::UpdateIncidentService < JrcServiceDesk::BaseService
  def call(unit_id:, incident_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[status severity impact cause workaround resolution owner_account_user_id])
    raise ArgumentError if values.empty?

    with_unit(unit_id) do |unit|
      row = JrcServiceDesk::Incident.where(account_id: context.account.id, unit_id: unit.id).lock.find(JrcServiceDesk::Input.id(incident_id))
      authorize!(row, :update?)
      verify_version!(row, expected_lock_version)
      raise ArgumentError, 'Resolved incidents are preserved' if row.status == 'resolved'

      row.owner_membership = assignee(values['owner_account_user_id'], unit) if values.key?('owner_account_user_id')
      apply_update(row, values.except('owner_account_user_id'))
      audit_changes(row)
      row
    end
  end

  private

  def apply_update(row, values)
    row.assign_attributes(values)
    raise ArgumentError, 'Explicit incident resolution required' if row.status == 'resolved' && row.resolution.blank?

    row.resolved_at = Time.current if row.status == 'resolved'
    row.save!
  end

  def audit_changes(row)
    changes = JrcServiceDesk::RecordedChanges.call(row.saved_changes.except('updated_at', 'lock_version'))
    JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(incident_id: row.id).find_each do |ticket|
      append_event!(ticket, 'incident_updated', 'incident_id' => row.id, 'changes' => changes)
    end
  end
end
