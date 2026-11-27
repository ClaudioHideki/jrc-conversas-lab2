# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'owned_recording_media'
require Rails.root.join('script/jrc_call_center_recording_ticket_seed')

# Read-only witness of the actual browser-created Ticket and immutable context.
class JrcContactCenter::SyntheticRecordingTicketEvidence
  def self.call(account_id, recording_id)
    SyntheticRecordedCallMedia.validate_environment!
    account = Account.find(JrcServiceDesk::Input.id(account_id))
    marker = SyntheticRecordedCallMedia.control!(account)
    id = JrcServiceDesk::Input.id(recording_id)
    raise 'Exact owned recording Ticket evidence required' unless marker.fetch('record_ids').include?(id)

    record = TelephonyCallRecord.where(account: account).find(id)
    call = JrcContactCenter::CallSession.find_by!(account: account, provider: record.provider, external_session_id: record.external_unique_id)
    control = account.settings.fetch(JrcContactCenter::SyntheticRecordingTicketSeed::MARKER)
    raise 'Exact source and owned native unit required' unless control.fetch('source_sha') == ENV.fetch('GITHUB_SHA')

    unit = JrcServiceDesk::Unit.where(account: account).find(control.fetch('unit_id'))
    actor = account.account_users.find(control.fetch('account_user_id'))
    tickets = JrcServiceDesk::Ticket.where(account: account, unit: unit).order(:id)
    rows = tickets.map { |ticket| present(ticket, actor, record, call) }
    { source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id.to_s, recording_id: record.id.to_s,
      call_session_id: call.id.to_s, call_id: call.external_session_id,
      unit_id: unit.id.to_s, actor_id: actor.user_id.to_s, actor_role: actor.role, ticket_count: rows.length, tickets: rows,
      read_only_witness: true, no_external_homologation: true }.merge(independent_counts(account))
  end

  def self.present(ticket, actor, record, call)
    marker = ticket.ticket_events.find_by!(event_type: 'creation_context_recorded')
    origin = marker.data.fetch('recording_origin')
    original = origin.fetch('recording_id') == record.id && origin.fetch('call_session_id') == call.id &&
               origin.fetch('call_id') == call.external_session_id && origin.fetch('contact_id') == call.contact_id
    membership = JrcServiceDesk::UnitMembership.where(account_id: ticket.account_id).find(ticket.created_by_membership_id)
    raise 'Exact native recording origin and actor required' unless original && membership.account_user_id == actor.id

    { id: ticket.id.to_s, title: ticket.title, requester_id: ticket.requester_id.to_s,
      creator_account_user_id: membership.account_user_id.to_s, creator_user_id: actor.user_id.to_s,
      idempotency_key: ticket.idempotency_key,
      origin: origin, creation_events: ticket.ticket_events.where(event_type: 'ticket_created').count,
      context_events: ticket.ticket_events.where(event_type: 'creation_context_recorded').count }
  end

  def self.independent_counts(account)
    rows = JrcContactCenter::Qualification.where(account: account).order(:id).map do |row|
      row.attributes.except('updated_at', 'overdue', 'exceeded_seconds').sort.to_h
    end
    { qualifications_semantic_sha256: Digest::SHA256.hexdigest(JSON.generate(rows)),
      ending_attempt_count: JrcContactCenter::EndingDestinationAttempt.where(account: account).count,
      native_project_tasks: JrcProjects::Task.where(account: account).count,
      PABX_commands: JrcContactCenter::Command.where(account: account).count }
  end
  private_class_method :present, :independent_counts
end
