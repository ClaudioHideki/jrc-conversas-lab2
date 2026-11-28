# frozen_string_literal: true

require_relative 'owned_recording_ticket_evidence'

# Reuse the exact owned recording, source actor and independent ACW witness.
# This reader never updates a profile, fixture, activity, audit or provider.
class JrcContactCenter::SyntheticRecordingRelationshipEvidence
  def self.call(account_id, recording_id)
    baseline = JrcContactCenter::SyntheticRecordingTicketEvidence.call(account_id, recording_id)
    account = Account.find(baseline.fetch(:account_id))
    rows = JrcCrm::Activity.where(account: account).where(
      "metadata -> 'control_desk_recording_origin' ->> 'recording_id' = ?", baseline.fetch(:recording_id)
    ).order(:id).map { |activity| present(activity, baseline) }
    baseline.slice(:source_sha, :account_id, :recording_id, :call_session_id, :actor_id, :actor_role, :read_only_witness,
                   :qualifications_semantic_sha256, :ending_attempt_count, :native_project_tasks, :PABX_commands)
            .merge(activity_count: rows.length, activities: rows, no_external_homologation: true)
  end

  def self.present(activity, baseline)
    origin = activity.metadata.fetch('control_desk_recording_origin')
    valid = origin.fetch('call_session_id').to_s == baseline.fetch(:call_session_id) &&
            activity.user_id.to_s == baseline.fetch(:actor_id)
    raise 'Exact owned recording Relationship origin required' unless valid

    action = JrcRelationship::Action.where(account_id: activity.account_id).find_by!(activity_id: activity.id)
    { id: activity.id.to_s, title: activity.title, status: activity.status, activity_type: activity.activity_type,
      user_id: activity.user_id.to_s, company_id: activity.company_id&.to_s, contact_id: activity.contact_id&.to_s,
      business_unit_id: activity.business_unit_id&.to_s, due_at: activity.due_at.iso8601,
      action_id: action.id.to_s, assignment_id: action.assignment_id.to_s,
      origin: origin, source_manifest: action.metadata.fetch('_source_ids'),
      request_sha256: action.metadata.fetch('control_desk_request_sha256') }
  end
  private_class_method :present
end
