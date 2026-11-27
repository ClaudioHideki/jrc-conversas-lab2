# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'owned_recording_media'

# Read-only witness, guarded by the existing exact 24-record owned fixture.
class JrcContactCenter::SyntheticRecordingCustomerLinkEvidence
  def self.call(account_id, recording_id)
    account, record, call = source!(account_id, recording_id)
    audits = Audited.audit_class.where(associated: account, auditable: call, comment: JrcContactCenter::RecordingCustomerLink::COMMENT)
    identity(account, record, call).merge(state(call, record, audits))
  end

  def self.identity(account, record, call)
    { source_sha: ENV.fetch('GITHUB_SHA'), account_id: account.id.to_s, recording_id: record.id.to_s,
      call_session_id: call.id.to_s, call_id: call.external_session_id, read_only_witness: true, no_external_homologation: true }
  end

  def self.state(call, record, audits)
    { contact_id: call.contact_id&.to_s, company_id: call.company_id&.to_s, lock_version: call.lock_version,
      unmodified_call_fields_sha256: digest(call.attributes.except('contact_id', 'company_id', 'lock_version', 'updated_at')),
      original_recording_sha256: digest(record.attributes), audit_count: audits.count,
      audits: audits.order(:id).map { |row| present(row) }, native_history: history(call) }
  end

  def self.source!(account_id, recording_id)
    SyntheticRecordedCallMedia.validate_environment!
    account = Account.find(JrcServiceDesk::Input.id(account_id))
    marker = SyntheticRecordedCallMedia.control!(account)
    identifier = JrcServiceDesk::Input.id(recording_id)
    raise 'Exact owned recording customer-link evidence required' unless marker.fetch('record_ids').include?(identifier)

    record = TelephonyCallRecord.where(account: account, provider: Pabx::Settings::PROVIDER).find(identifier)
    call = JrcContactCenter::CallSession.find_by!(account: account, provider: record.provider, external_session_id: record.external_unique_id)
    [account, record, call]
  end

  def self.present(row)
    { id: row.id.to_s, user_id: row.user_id.to_s, request_id: row.request_uuid, changes: row.audited_changes,
      created_at: row.created_at.iso8601 }
  end

  def self.history(call)
    rows = JrcContactCenter::Qualification.where(account: call.account, call_session: call).order(:id).map do |row|
      row.attributes.except('updated_at', 'overdue', 'exceeded_seconds').sort.to_h
    end
    { qualifications_semantic_sha256: digest(rows), ending_origins_semantic_sha256: origin_digest(call),
      observations: JrcContactCenter::CallObservation.where(account: call.account, call_session: call).count,
      commands: JrcContactCenter::Command.where(account: call.account).count }
  end

  def self.origin_digest(call)
    rows = JrcContactCenter::EndingActionOrigin.where(account: call.account, call_session_id: call.id).order(:id).map do |row|
      row.attributes.sort.to_h
    end
    digest(rows)
  end

  def self.digest(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end
  private_class_method :identity, :state, :source!, :present, :history, :origin_digest, :digest
end
