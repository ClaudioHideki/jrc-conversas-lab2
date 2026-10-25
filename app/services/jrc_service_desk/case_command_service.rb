# frozen_string_literal: true

class JrcServiceDesk::CaseCommandService < JrcServiceDesk::BaseService
  ACTIONS = %w[update transition reopen link_tickets unlink_ticket link_incidents unlink_incident comment attach withdraw_attachment link_resource
               unlink_resource create_project_task create_article request_approval external_reference rescan_attachment].freeze

  def call(unit_id:, incident_id:, action:, attributes:, expected_lock_version:, idempotency_key:, files: [])
    raise ArgumentError, 'Unknown command' unless ACTIONS.include?(action)

    key = JrcServiceDesk::Input.request_key(idempotency_key)
    values = JrcServiceDesk::Input.attributes(attributes, fields_for(action))
    uploads = JrcServiceDesk::InteractionAttachments.prepare(files)
    raise ArgumentError, 'Files require attachment command' if action != 'attach' && uploads.any?

    fingerprint = JrcServiceDesk::CanonicalJson.digest('action' => action, 'attributes' => values,
                                                       'files' => uploads.map do |file|
                                                         file.slice(:filename, :content_type, :sha256)
                                                       end)
    with_unit(unit_id) do |unit|
      row = JrcServiceDesk::IncidentPolicy::Scope.new(context.to_h,
                                                      JrcServiceDesk::Incident).resolve.where(unit_id: unit.id).lock.find(JrcServiceDesk::Input.id(incident_id))
      authorize!(row, :update?)
      prior = row.incident_entries.find_by(actor_membership: actor_membership, idempotency_key: key)
      if prior
        raise JrcServiceDesk::IdempotencyConflict unless prior.request_fingerprint == fingerprint

        next { row: row, entry: prior, replayed: true }
      end
      verify_version!(row, expected_lock_version)
      outcome = execute(row, unit, action, values, uploads)
      entry = JrcServiceDesk::CaseJournal.append!(row: row, actor: actor_membership, key: key, fingerprint: fingerprint,
                                                  event: outcome.fetch(:event), data: outcome.fetch(:data, {}), body: outcome[:body], uploads: uploads)
      { row: row, entry: entry, replayed: false }
    end
  end

  private

  def fields_for(action)
    return JrcServiceDesk::CaseInput::FIELDS if action == 'update'

    { 'transition' => %w[status resolution], 'reopen' => %w[reason], 'link_tickets' => %w[ids], 'unlink_ticket' => %w[id],
      'link_incidents' => %w[ids], 'unlink_incident' => %w[id], 'comment' => %w[body], 'attach' => %w[body],
      'withdraw_attachment' => %w[entry_id attachment_id reason], 'link_resource' => %w[kind id], 'unlink_resource' => %w[kind id],
      'create_project_task' => %w[project_id task], 'create_article' => %w[portal_id title content category_id],
      'request_approval' => %w[issuer_company_id business_unit_id], 'external_reference' => %w[ticket_id note_id], 'rescan_attachment' => %w[entry_id attachment_id] }.fetch(action)
  end

  def execute(row, unit, action, values, uploads)
    case action
    when 'update' then update(row, unit, values)
    when 'transition', 'reopen' then transition(row, action, values)
    when 'link_tickets', 'unlink_ticket' then ticket_links(row, unit, action, values)
    when 'link_incidents', 'unlink_incident' then incident_links(row, unit, action, values)
    when 'comment', 'attach'
      authorize!(row, :comment?)
      body = text(values['body'], nullable: true).to_s.strip
      raise ArgumentError, 'Comment required' if action == 'comment' && body.empty?
      raise ArgumentError, 'Upload required' if action == 'attach' && uploads.empty?
      raise ArgumentError, 'Comment too long' if body.length > 20_000

      row.touch
      { event: action == 'comment' ? 'note_added' : 'attachment_added', body: body, data: { 'visibility' => 'internal' } }
    when 'rescan_attachment'
      authorize!(row, :comment?)
      entry = row.incident_entries.find(JrcServiceDesk::Input.id(values.fetch('entry_id')))
      file = entry.files.find(JrcServiceDesk::Input.id(values.fetch('attachment_id')))
      raise ArgumentError, 'Attachment already withdrawn' if row.incident_entries.where(event_type: 'attachment_withdrawn').where(
        "data->>'attachment_id' = ?", file.id.to_s
      ).exists?

      row.touch
      { event: 'updated', data: { 'attachment_rescan_entry_id' => entry.id, 'attachment_id' => file.id.to_s } }
    when 'external_reference'
      ticket = JrcServiceDesk::CaseAssociations.tickets(row, context).find(JrcServiceDesk::Input.id(values.fetch('ticket_id')))
      note = ticket.ticket_notes.find(JrcServiceDesk::Input.id(values.fetch('note_id')))
      authorize!(note, :show?)
      raise ArgumentError unless %w[customer public_without_notification].include?(note.visibility)

      row.touch
      { event: 'updated',
        data: { 'native_action' => action, 'ticket_ids' => [ticket.id.to_s], 'note_id' => note.id.to_s, 'visibility' => 'customer' } }
    when 'withdraw_attachment' then withdraw(row, values)
    when 'link_resource', 'unlink_resource', 'create_project_task', 'create_article', 'request_approval' then native_resource(row, action, values)
    end
  end

  def editable!(row)
    raise ArgumentError, 'Reopen the terminal record before editing' if %w[resolved closed].include?(row.status)
  end

  def update(row, unit, values)
    editable!(row)
    data = JrcServiceDesk::CaseInput.call(values)
    row.owner_membership = assignee(data.delete('owner_account_user_id'), unit) if data.key?('owner_account_user_id')
    { 'service_id' => JrcServiceDesk::Service, 'category_id' => JrcServiceDesk::Category }.each do |key, model|
      row.public_send("#{key.delete_suffix('_id')}=", reference(model, data.delete(key), unit)) if data.key?(key)
    end
    row.assign_attributes(data)
    row.save!
    changes = JrcServiceDesk::RecordedChanges.call(row.saved_changes.except('updated_at', 'lock_version'))
    # A no-op still receives a durable receipt, without inventing a transition.
    { event: 'updated', data: { 'changes' => changes } }
  end

  def transition(row, action, values)
    before = row.status
    if action == 'reopen'
      authorize!(row, :reopen?)
      row.status = JrcServiceDesk::IncidentWorkflow.reopen!(from: before, reason: values['reason'])
      row.closed_at = nil
    else
      target = values.fetch('status')
      resolution = values.fetch('resolution', row.resolution)
      grant = JrcServiceDesk::IncidentWorkflow.validate!(from: before, target: target, resolution: resolution)
      authorize!(row, grant)
      row.status = target
      row.resolution = resolution if %w[resolved closed].include?(target)
      row.resolved_at = Time.current if target == 'resolved'
      row.closed_at = Time.current if target == 'closed'
    end
    row.save!
    { event: action == 'reopen' ? 'reopened' : 'transitioned', body: values['reason'],
      data: { 'from' => before, 'to' => row.status, 'resolution' => row.resolution,
              'resolved_at' => row.resolved_at&.iso8601(6), 'closed_at' => row.closed_at&.iso8601(6) } }
  end

  def ticket_links(row, unit, action, values)
    editable!(row)
    ids = action == 'link_tickets' ? JrcServiceDesk::CaseInput.ids(values.fetch('ids')) : [JrcServiceDesk::Input.id(values.fetch('id'))]
    tickets = ids.map do |id|
      record = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: unit.id).lock.find(id)
      authorize!(record, :update?)
      record
    end
    tickets.each do |ticket|
      if action == 'link_tickets'
        link = row.case_links.find_or_initialize_by(ticket: ticket)
        link.assign_attributes(account: context.account, unit: unit, created_by_membership: actor_membership) if link.new_record?
        link.active = true
        link.save!
      else
        link = row.case_links.active.find_by(ticket: ticket)
        raise ActiveRecord::RecordNotFound unless link || ticket.incident_id == row.id

        link&.update!(active: false)
        ticket.update!(incident_id: nil) if ticket.incident_id == row.id
        row.primary_ticket_id = nil if row.primary_ticket_id == ticket.id
      end
      append_event!(ticket, action == 'link_tickets' ? 'incident_linked' : 'incident_updated',
                    'incident_id' => row.id, 'changes' => { 'link_active' => action == 'link_tickets' })
    end
    row.save! if row.changed?
    row.touch
    { event: action == 'link_tickets' ? 'tickets_linked' : 'ticket_unlinked', data: { 'ticket_ids' => ids.map(&:to_s) } }
  end

  def incident_links(row, unit, action, values)
    editable!(row)
    raise ArgumentError, 'Select a problem as the source' unless row.resource_kind == 'problem'

    ids = action == 'link_incidents' ? JrcServiceDesk::CaseInput.ids(values.fetch('ids')) : [JrcServiceDesk::Input.id(values.fetch('id'))]
    targets = ids.map do |id|
      target = JrcServiceDesk::IncidentPolicy::Scope.new(context.to_h, JrcServiceDesk::Incident).resolve.where(unit_id: unit.id,
                                                                                                               resource_kind: 'incident').lock.find(id)
      authorize!(target, :update?)
      target
    end
    targets.each do |target|
      if action == 'link_incidents'
        link = row.case_links.find_or_initialize_by(related_incident: target)
        link.assign_attributes(account: context.account, unit: unit, created_by_membership: actor_membership) if link.new_record?
        link.active = true
        link.save!
      else
        row.case_links.active.find_by!(related_incident: target).update!(active: false)
      end
    end
    row.touch
    { event: action == 'link_incidents' ? 'incidents_linked' : 'incident_unlinked', data: { 'related_incident_ids' => ids.map(&:to_s) } }
  end

  def native_resource(row, action, values)
    editable!(row)
    raise ArgumentError unless row.resource_kind == 'problem'

    resources = JrcServiceDesk::CaseNativeResources.new(row: row, context: context, actor: actor_membership)
    records = []
    if %w[link_resource unlink_resource].include?(action)
      kind = values.fetch('kind')
      record = resources.find(kind, values.fetch('id'))
      if action == 'link_resource'
        resources.link(kind, record)
      else
        row.resource_links.where(active: true).find_by!(JrcServiceDesk::CaseNativeResources::TARGETS.fetch(kind) => record).update!(active: false)
      end
      records << [kind, record.id]
    elsif action == 'create_project_task'
      project = JrcOperations::Access.projects(context.account_user).find(JrcServiceDesk::Input.id(values.fetch('project_id')))
      task = JrcServiceDesk::Input.attributes(values.fetch('task'), JrcProjects::Tasks::Create::FIELDS + ['board_column_id'])
      record = JrcProjects::Tasks::Create.call(account_user: context.account_user, project: project, attributes: task,
                                               correlation_id: "service-desk-problem:#{row.id}")
      resources.link('tasks', record)
      records << ['tasks', record.id]
    elsif action == 'create_article'
      portal = context.account.portals.find(JrcServiceDesk::Input.id(values.fetch('portal_id')))
      article = portal.articles.new(account: context.account, author: context.user, title: values.fetch('title'),
                                    content: values.fetch('content'), locale: portal.default_locale, status: 'draft')
      article.category = portal.categories.find(JrcServiceDesk::Input.id(values['category_id'])) if values['category_id']
      JrcServiceDesk::NativeExecutionContext.with(context.to_h) { authorize!(article, :create?) }
      article.save!
      resources.link('articles', article)
      records << ['articles', article.id]
    else
      company = JrcServiceDesk::Input.id(values.fetch('issuer_company_id'))
      business_unit = values['business_unit_id'] && JrcServiceDesk::Input.id(values['business_unit_id'])
      JrcApprovals::Authorization.new(account: context.account, user: context.user).authorize!('request_create', company_id: company,
                                                                                                                 unit_id: business_unit)
      row.update!(approval_issuer_company_id: company, approval_business_unit_id: business_unit)
      requests = JrcApprovals::Requests.new(account: context.account, user: context.user).create!(key: JrcServiceDesk::ProblemApprovalCatalog::KEY,
                                                                                                  resource_id: row.id, idempotency_key: SecureRandom.uuid)
      raise ArgumentError, 'No published authorized approval policy' if requests.empty?

      requests.each do |request|
        resources.link('approvals', request)
        records << ['approvals', request.id]
      end
    end
    row.touch
    { event: 'updated', data: { 'native_action' => action, 'native_resources' => records } }
  end

  def withdraw(row, values)
    authorize!(row, :comment?)
    reason = text(values.fetch('reason')).strip
    raise ArgumentError, 'Reason required' unless reason.length.between?(1, 4000)

    entry = row.incident_entries.find(JrcServiceDesk::Input.id(values.fetch('entry_id')))
    file = entry.files.find(JrcServiceDesk::Input.id(values.fetch('attachment_id')))
    raise ArgumentError, 'Attachment already withdrawn' if row.incident_entries.where(event_type: 'attachment_withdrawn').where(
      "data->>'attachment_id' = ?", file.id.to_s
    ).exists?

    row.touch
    { event: 'attachment_withdrawn', body: reason, data: { 'entry_id' => entry.id.to_s, 'attachment_id' => file.id.to_s } }
  end
end
