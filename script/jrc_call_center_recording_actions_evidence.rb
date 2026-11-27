# frozen_string_literal: true

# Read-only SQL witness of one existing owned fixture, never a setup or execution command.
class JrcContactCenter::SyntheticRecordingActionsEvidence
  def self.call(account_id, recording_id, qualification_id)
    new(account_id, recording_id, qualification_id).call
  end

  def initialize(account_id, recording_id, qualification_id)
    @account = Account.find(JrcServiceDesk::Input.id(account_id))
    @recording_id = JrcServiceDesk::Input.id(recording_id)
    @qualification_id = JrcServiceDesk::Input.id(qualification_id)
  end

  def call
    owned_environment!
    record = TelephonyCallRecord.where(account: @account).find(@recording_id)
    call = JrcContactCenter::CallSession.find_by!(account: @account, provider: record.provider, external_session_id: record.external_unique_id)
    row = JrcContactCenter::Qualification.where(account: @account, call_session: call).find(@qualification_id)
    { source_sha: ENV.fetch('GITHUB_SHA'), account_id: @account.id.to_s, recording_id: record.id.to_s,
      call_session_id: call.id.to_s, qualification_id: row.id.to_s,
      account_user_id: row.account_user_id.to_s, started_at: row.started_at, completed_at: row.completed_at,
      read_only_witness: true, no_external_homologation: true }.merge(native_counts)
  end

  private

  def native_counts
    { native_qualification_count: JrcContactCenter::Qualification.where(account: @account).count,
      native_action_origin_count: JrcContactCenter::EndingActionOrigin.where(account: @account).count,
      provider_command_count: JrcContactCenter::Command.where(account: @account).count }
  end

  def owned_environment!
    config = ApplicationRecord.connection_db_config
    marker = @account.settings.fetch(JrcContactCenter::SyntheticRecordingsSeed::MARKER, {})
    conditions = [
      Rails.env.test?, ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted',
      ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116',
      config.database == 'jrc_sd_bc_portal_concurrency_20261025_test', config.configuration_hash[:host] == '127.0.0.1',
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15', @account.name.start_with?('SYNTHETIC pause '),
      @account.name.end_with?('-recordings'), marker['source_sha'] == ENV.fetch('GITHUB_SHA'),
      marker.fetch('record_ids', []).include?(@recording_id)
    ]
    raise 'Owned recording actions evidence required' unless conditions.all?
  end
end

require Rails.root.join('script/jrc_call_center_recordings_seed')
puts JrcContactCenter::SyntheticRecordingActionsEvidence.call(*ARGV).to_json
