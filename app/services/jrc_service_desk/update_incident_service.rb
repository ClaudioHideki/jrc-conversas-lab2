# frozen_string_literal: true

class JrcServiceDesk::UpdateIncidentService < JrcServiceDesk::BaseService
  def call(unit_id:, incident_id:, attributes:, expected_lock_version:)
    values = JrcServiceDesk::CaseInput.call(attributes)
    raise ArgumentError if values.empty?

    with_unit(unit_id) do |unit|
      row = JrcServiceDesk::Incident.where(account_id: context.account.id, unit_id: unit.id).lock.find(JrcServiceDesk::Input.id(incident_id))
      authorize!(row, :update?)
      verify_version!(row, expected_lock_version)
      raise ArgumentError, 'Resolved incidents are preserved' if %w[resolved closed].include?(row.status)

      row.owner_membership = assignee(values['owner_account_user_id'], unit) if values.key?('owner_account_user_id')
      %w[service category].each do |name|
        if values.key?("#{name}_id")
          row.public_send("#{name}=",
                          reference("JrcServiceDesk::#{name.classify}".constantize, values["#{name}_id"], unit))
        end
      end
      if values['status'] && values['status'] != row.status
        action = JrcServiceDesk::IncidentWorkflow.validate!(from: row.status, target: values['status'],
                                                            resolution: values.fetch('resolution', row.resolution))
        authorize!(row, action)
      end
      apply_update(row, values.except('owner_account_user_id', 'service_id', 'category_id'))
      audit_changes(row)
      row
    end
  end

  private

  def apply_update(row, values)
    row.assign_attributes(values)
    raise ArgumentError, 'Explicit incident resolution required' if %w[resolved closed].include?(row.status) && row.resolution.blank?

    row.resolved_at = Time.current if row.status == 'resolved'
    row.closed_at = Time.current if row.status == 'closed'
    row.save!
  end

  def audit_changes(row)
    changes = JrcServiceDesk::RecordedChanges.call(row.saved_changes.except('updated_at', 'lock_version'))
    JrcServiceDesk::CaseJournal.append!(row: row, actor: actor_membership, event: 'updated', data: { 'changes' => changes },
                                        key: SecureRandom.uuid, fingerprint: JrcServiceDesk::CanonicalJson.digest(changes))
    JrcServiceDesk::CaseAssociations.tickets(row, context).find_each do |ticket|
      append_event!(ticket, 'incident_updated', 'incident_id' => row.id, 'changes' => changes)
    end
  end
end
