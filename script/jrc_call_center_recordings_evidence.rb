# frozen_string_literal: true

# Read-only receipt for owned synthetic Chrome accounts; excludes numbers, media, credentials and provider references.
require Rails.root.join('spec/integration/jrc_contact_center/owned_recording_media')
account = Account.find(ARGV.fetch(0))
control = SyntheticRecordedCallMedia.control!(account)
comments = %w[jrc_contact_center_recording_access_v1 jrc_contact_center_recording_reproduction_v1]
audits = Audited.audit_class.where(associated: account, comment: comments).order(:id)
rows = audits.map do |audit|
  { id: audit.id, user_id: audit.user_id, record_id: audit.auditable_id,
    auditable_type: audit.auditable_type, action: audit.action, changes: audit.audited_changes }
end
puts({ source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id,
       owned_record_count: control.fetch('record_ids').length, operations: rows,
       media_sha256: Digest::SHA256.hexdigest(SyntheticRecordedCallMedia.wav), media_bytes: SyntheticRecordedCallMedia.wav.bytesize,
       provider_boundary: 'synthetic_in_memory_wav_not_external_homologation' }.to_json)
