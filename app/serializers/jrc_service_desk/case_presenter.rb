# frozen_string_literal: true

class JrcServiceDesk::CasePresenter
  def initialize(context:)
    @context = context.is_a?(JrcServiceDesk::OperationalContext) ? context : JrcServiceDesk::OperationalContext.new(context)
  end

  def call(row)
    policy = JrcServiceDesk::IncidentPolicy.new(@context.to_h, row)
    raise Pundit::NotAuthorizedError unless policy.show?

    JrcServiceDesk::OperationsPresenter.new(context: @context).call('incidents', row).merge(
      code: "#{row.resource_kind == 'problem' ? 'PRB' : 'INC'}-#{row.id.to_s.rjust(7, '0')}",
      owner_name: row.owner_membership&.account_user&.user&.name, service: named(row.service), category: named(row.category),
      operator_company: named(row.unit.operator_company), unit: named(row.unit), details: row.details,
      started_at: row.started_at&.iso8601(6), resolved_at: row.resolved_at&.iso8601(6), closed_at: row.closed_at&.iso8601(6),
      created_at: row.created_at.iso8601(6), updated_at: row.updated_at.iso8601(6),
      related_count: JrcServiceDesk::CaseAssociations.related(row, @context).count,
      allowed_transitions: JrcServiceDesk::IncidentWorkflow::TRANSITIONS.fetch(row.status, []).select do |target|
        policy.public_send(JrcServiceDesk::IncidentWorkflow.action_for(row.status, target))
      end,
      permissions: { show: true, update: policy.update? && editable?(row), link: policy.update? && editable?(row),
                     comment: policy.comment?, reopen: policy.reopen? && !editable?(row) }
    )
  end

  def entry(row)
    Pundit.authorize(@context.to_h, row.incident, :show?)
    data = row.data.deep_dup
    if data['ticket_ids']
      data['ticket_ids'] =
        Pundit.policy_scope!(@context.to_h, JrcServiceDesk::Ticket).where(unit_id: row.unit_id, id: data['ticket_ids']).pluck(:id).map(&:to_s)
    end
    data.delete('note_id') if data['native_action'] == 'external_reference' && data['ticket_ids'].blank?
    if data['related_incident_ids']
      data['related_incident_ids'] =
        Pundit.policy_scope!(@context.to_h, JrcServiceDesk::Incident).where(unit_id: row.unit_id,
                                                                            id: data['related_incident_ids']).pluck(:id).map(&:to_s)
    end
    if data['native_resources']
      resources = JrcServiceDesk::CaseNativeResources.new(row: row.incident, context: @context)
      data['native_resources'] = data['native_resources'].select do |kind, id|
        resources.find(kind, id)
        true
      rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
        false
      end
    end
    { id: row.id.to_s, event_type: row.event_type, body: row.body, data: data,
      actor_name: row.actor_membership.account_user.user.name, occurred_at: row.created_at.iso8601(6),
      files: row.files.map { |file| attachment(row, file) } }
  end

  def attachment(entry, file)
    withdrawn = entry.incident.incident_entries.where(event_type: 'attachment_withdrawn').where("data->>'attachment_id' = ?", file.id.to_s).exists?
    scan = file.blob.metadata['service_desk_scan_state'] || 'unavailable'
    { id: file.id.to_s, entry_id: entry.id.to_s, filename: file.filename.to_s, byte_size: file.byte_size,
      content_type: file.content_type, visibility: 'internal', scan_state: scan, withdrawn: withdrawn,
      downloadable: !withdrawn && JrcServiceDesk::AttachmentScanner.clean?(file.blob), created_at: entry.created_at.iso8601(6) }
  end

  private

  def named(record)
    record ? { id: record.id.to_s, name: record.name } : nil
  end

  def editable?(row)
    !%w[resolved closed].include?(row.status)
  end
end
