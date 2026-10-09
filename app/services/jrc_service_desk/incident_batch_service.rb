# frozen_string_literal: true

# Finite, all-or-nothing incident operations using native notes/linking and audits.
# No bulk close/send/recatalogue is inferred from a grouping suggestion.
class JrcServiceDesk::IncidentBatchService < JrcServiceDesk::BaseService
  PURPOSE = 'jrc_sd_incident_batch_v1'
  FIELDS = %w[action tickets body visibility].freeze

  def preview(unit_id:, incident_id:, attributes:)
    values = normalized(attributes)
    with_batch(unit_id, incident_id, values) do |incident, tickets|
      verify_versions!(tickets, values)
      verify_links!(incident, tickets, values)
      plans = values['action'] == 'note' ? note_previews(tickets, values) : []
      binding = binding(incident, tickets, values)
      { receipt: verifier.generate(binding, purpose: PURPOSE, expires_in: 5.minutes), action: values['action'],
        ticket_ids: tickets.map { |ticket| ticket.id.to_s }, notes: plans, expires_at: 5.minutes.from_now.iso8601(6) }
    end
  end

  def call(unit_id:, incident_id:, attributes:, idempotency_key:, receipt:, note_receipts: {})
    values = normalized(attributes)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_batch(unit_id, incident_id, values) do |incident, tickets|
      auditor = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership)
      fingerprint = JrcServiceDesk::CanonicalJson.digest('incident_id' => incident.id, 'attributes' => values)
      prior = auditor.prior(key)
      next replay!(auditor, prior, fingerprint, incident) if prior

      verify_versions!(tickets, values)
      verify_links!(incident, tickets, values)
      approved = verifier.verified(receipt, purpose: PURPOSE) if receipt.is_a?(String)
      raise JrcServiceDesk::PublicationPreviewError unless approved == binding(incident, tickets, values)

      result = values['action'] == 'link' ? link!(incident, tickets) : notes!(tickets, values, key, note_receipts)
      auditor.write!(resource: 'incident_batch', record: incident, action: 'update', before: {},
                     after: result, key: key, fingerprint: fingerprint)
      result
    end
  end

  # Independent authorized readback: read persisted native notes/tickets, not only ACK.
  def readback(unit_id:, incident_id:, idempotency_key:)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    with_unit(unit_id) do |unit|
      incident = JrcServiceDesk::IncidentPolicy::Scope.new(context.to_h, JrcServiceDesk::Incident).resolve
                                                      .where(unit_id: unit.id).find(JrcServiceDesk::Input.id(incident_id))
      authorize!(incident, :show?)
      auditor = JrcServiceDesk::ConfigurationAudit.new(context: context, membership: actor_membership)
      audit = auditor.prior(key)
      raise ActiveRecord::RecordNotFound unless audit && audit.auditable_id == incident.id && audit.auditable_type == incident.class.base_class.name

      info = auditor.metadata(audit)
      raise ActiveRecord::RecordNotFound unless info['resource'] == 'incident_batch'

      result = info.fetch('after')
      tickets = result.fetch('ticket_ids').map do |id|
        ticket = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: unit.id).find(id)
        authorize!(ticket, :show?)
        ticket
      end
      if result.fetch('action') == 'note'
        notes = result.fetch('note_ids').map do |id|
          note = JrcServiceDesk::TicketNote.where(account_id: context.account.id, unit_id: unit.id, ticket_id: tickets.map(&:id)).find(id)
          authorize!(note, :show?)
          note.id.to_s
        end
        result = result.merge('note_ids' => notes)
      else
        raise JrcServiceDesk::IdempotencyConflict unless tickets.all? { |ticket| ticket.incident_id == incident.id }
      end
      result
    end
  end

  private

  def normalized(attributes)
    values = JrcServiceDesk::Input.attributes(attributes, FIELDS)
    raise ArgumentError, 'Unsupported batch action' unless %w[link note].include?(values['action'])

    rows = values.fetch('tickets')
    raise ArgumentError, 'Select 1 to 100 explicit tickets' unless rows.is_a?(Array) && rows.length.between?(1, 100)

    values['tickets'] = rows.map do |row|
      item = JrcServiceDesk::Input.attributes(row, %w[id lock_version])
      { 'id' => JrcServiceDesk::Input.id(item.fetch('id')), 'lock_version' => JrcServiceDesk::Input.version(item.fetch('lock_version')) }
    end.sort_by { |row| row['id'] }
    raise ArgumentError, 'Duplicate ticket' unless values['tickets'].map { |row| row['id'] }.uniq.size == rows.size

    if values['action'] == 'note'
      raise ArgumentError, 'Internal or silent public progress only' unless %w[internal public_without_notification].include?(values['visibility'])
      raise ArgumentError, 'Progress text required' unless values['body'].is_a?(String) && values['body'].strip.length.between?(1, 4000)
    elsif values.key?('body') || values.key?('visibility')
      raise ArgumentError, 'Link operation does not publish content'
    end
    values
  end

  def with_batch(unit_id, incident_id, values)
    with_unit(unit_id) do |unit|
      incident = JrcServiceDesk::IncidentPolicy::Scope.new(context.to_h, JrcServiceDesk::Incident).resolve.where(unit_id: unit.id)
                                                      .lock.find(JrcServiceDesk::Input.id(incident_id))
      authorize!(incident, :update?)
      tickets = values['tickets'].map do |row|
        ticket = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: unit.id).lock.find(row['id'])
        authorize!(ticket, values['action'] == 'link' ? :update? : :add_note?)
        if values['action'] == 'note'
          JrcServiceDesk::InteractionVisibility.authorize_publication!(context, ticket, visibility: values['visibility'], audience_team_id: nil)
        end
        ticket
      end
      yield incident, tickets
    end
  end

  def verify_versions!(tickets, values)
    tickets.zip(values['tickets']).each { |ticket, requested| verify_version!(ticket, requested['lock_version']) }
  end

  def verify_links!(incident, tickets, values)
    valid = tickets.all? do |ticket|
      values['action'] == 'link' ? ticket.incident_id.nil? || ticket.incident_id == incident.id : ticket.incident_id == incident.id
    end
    raise JrcServiceDesk::IdempotencyConflict, 'Incident membership changed' unless valid
    raise ArgumentError, 'Cannot add tickets to a resolved incident' if values['action'] == 'link' && incident.status == 'resolved'
  end

  def binding(incident, tickets, values)
    { 'account_id' => context.account.id, 'unit_id' => incident.unit_id, 'actor_id' => context.account_user.id,
      'incident_id' => incident.id, 'incident_lock_version' => incident.lock_version,
      'tickets' => tickets.map { |ticket| [ticket.id, ticket.lock_version, ticket.incident_id] },
      'digest' => JrcServiceDesk::CanonicalJson.digest(values) }
  end

  def note_previews(tickets, values)
    tickets.map do |ticket|
      preview = JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: note_attributes(values))
      { ticket_id: ticket.id.to_s, body: values['body'], visibility: values['visibility'], receipt: preview[:receipt] }
    end
  end

  def note_attributes(values)
    { 'body' => values['body'], 'visibility' => values['visibility'], 'notification_channels' => [] }
  end

  def link!(incident, tickets)
    tickets.each do |ticket|
      next if ticket.incident_id == incident.id

      ticket.update!(incident: incident)
      append_event!(ticket, 'incident_linked', 'incident_id' => incident.id, 'primary_ticket_id' => incident.primary_ticket_id)
    end
    { 'ticket_ids' => tickets.map { |ticket| ticket.id.to_s }, 'incident_id' => incident.id.to_s, 'action' => 'link' }
  end

  def notes!(tickets, values, key, receipts)
    raise ArgumentError unless receipts.is_a?(Hash)

    note_ids = tickets.map do |ticket|
      note = JrcServiceDesk::AddNoteService.new(user_context: context.to_h).call(
        ticket_id: ticket.id, attributes: note_attributes(values), preview_receipt: receipts[ticket.id.to_s],
        idempotency_key: "batch:#{Digest::SHA256.hexdigest(key)}:#{ticket.id}"
      )
      note.id.to_s
    end
    { 'ticket_ids' => tickets.map { |ticket| ticket.id.to_s }, 'note_ids' => note_ids, 'action' => 'note' }
  end

  def replay!(auditor, audit, fingerprint, incident)
    info = auditor.metadata(audit)
    unless info['resource'] == 'incident_batch' && info['fingerprint'] == fingerprint && audit.auditable_id == incident.id &&
           audit.auditable_type == incident.class.base_class.name
      raise JrcServiceDesk::IdempotencyConflict, 'Batch key reused for a different operation'
    end

    info.fetch('after')
  end

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
