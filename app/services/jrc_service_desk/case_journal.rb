# frozen_string_literal: true

module JrcServiceDesk::CaseJournal
  module_function

  def append!(row:, actor:, event:, data:, key:, fingerprint:, body: nil, uploads: [])
    entry = JrcServiceDesk::IncidentEntry.new(account: row.account, unit: row.unit, incident: row,
                                              actor_membership: actor, event_type: event, body: body, data: JrcServiceDesk::RecordedChanges.call(data).merge('version_after' => row.lock_version),
                                              idempotency_key: key, request_fingerprint: fingerprint)
    entry.files.attach(uploads.map { |file| file.except(:sha256) }) if uploads.any?
    JrcServiceDesk::IncidentEntry.no_touching { entry.save! }
    entry
  end
end
