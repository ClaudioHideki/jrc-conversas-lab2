# frozen_string_literal: true

require Rails.root.join('spec/integration/jrc_contact_center/owned_quality_source')

# Read-only verification against actual native SQL; never executes a correction, job, command or provider request.
module JrcContactCenter::SyntheticQualityReviewEvidence
  def self.read(account_id, recording_id)
    SyntheticRecordedCallMedia.validate_environment!
    account = Account.find(account_id)
    marker = SyntheticRecordedCallMedia.control!(account)
    raise 'Exact owned recording required' unless marker.fetch('record_ids').include?(recording_id)

    record = TelephonyCallRecord.where(account: account).find(recording_id)
    original = SyntheticRecordedCallQuality.analysis(account.id, record.external_unique_id)
    snapshot = JrcContactCenter::QualityAnalysisSnapshot.new(analysis: original, authorized_call_id: record.external_unique_id)
    rows = JrcContactCenter::QualityReviewRevision.where(account: account, recording: record).order(:revision).to_a
    require_original!(rows, snapshot)
    { source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id, recording_id: record.id,
      actual_native_revisions: rows.map { |row| JrcContactCenter::QualityReviewPresentation.revision(row) },
      native_audits: audits(account, rows),
      source_boundary: 'synthetic_original_analysis_not_external_Nico_homologation',
      independent_audio_reference_sha256: Digest::SHA256.hexdigest(record.recording_reference),
      ending_destination_actions: JrcContactCenter::EndingDestinationAttempt.where(account: account).count,
      PABX_commands: JrcContactCenter::Command.where(account: account).count, existing_records_modified_by_evidence: false }
  end

  def self.require_original!(rows, snapshot)
    original = JrcContactCenter::QualityReviewPresentation.original(snapshot)
    unchanged = rows.all? { |row| row.original_analysis == original && row.source_sha256 == snapshot.sha256 }
    raise 'Original analysis or immutable source changed' unless unchanged
    raise 'Strict native revision sequence required' unless rows.map(&:revision) == (1..rows.length).to_a
  end

  def self.audits(account, rows)
    Audited.audit_class.where(auditable_type: 'JrcContactCenter::QualityReviewRevision', auditable_id: rows.map(&:id),
                              associated_type: 'Account', associated_id: account.id).order(:id).map do |audit|
      audit.attributes.slice('id', 'auditable_type', 'auditable_id', 'action', 'user_id', 'created_at', 'audited_changes')
    end
  end
end

