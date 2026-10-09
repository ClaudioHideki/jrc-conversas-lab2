# frozen_string_literal: true

# Raw historical conditions are projected only after the native snapshot read policy.
class JrcServiceDesk::SlaSnapshotPresenter
  def initialize(user_context:)
    @context = user_context
  end

  def call(snapshot, receipt: false)
    readable = JrcServiceDesk::SlaSnapshotPolicy.new(@context, snapshot).show?
    raise Pundit::NotAuthorizedError unless readable || receipt

    result = { id: snapshot.id.to_s, version: snapshot.version, permissions: { show: readable } }
    return result unless readable

    result.merge(payload_digest: snapshot.payload_digest,
                 source: { system: snapshot.source_system, reference: snapshot.source_reference, version: snapshot.source_version },
                 policy: { key: snapshot.policy_key, version: snapshot.policy_version },
                 calendar: { key: snapshot.calendar_key, version: snapshot.calendar_version, scope: snapshot.calendar_scope },
                 timezone: snapshot.timezone, captured_at: snapshot.captured_at.iso8601(6), applied_at: snapshot.applied_at.iso8601(6),
                 conditions: { contract: snapshot.contract_conditions, policy: snapshot.policy_conditions, calendar: snapshot.calendar_conditions })
  end
end
