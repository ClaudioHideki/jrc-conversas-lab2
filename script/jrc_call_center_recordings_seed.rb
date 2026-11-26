# frozen_string_literal: true

# Exclusive synthetic records for the existing native browser runner. Never imports a real CDR or issues a provider request.
class JrcContactCenter::SyntheticRecordingsSeed
  MARKER = 'jrc_cc_owned_recordings_fixture'
  RIGHTS = %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen].freeze

  def self.call(account:, operator:, viewer:, queues:)
    new(account, operator, viewer, queues).call
  end

  def initialize(account, operator, viewer, queues)
    @account = account
    @operator = operator
    @viewer = viewer
    @queues = queues
    @nonce = SecureRandom.hex(12)
  end

  def call
    owned_environment!
    configure_roles
    configure_native_history
    rows = create_rows
    install_marker!(rows.values + (1..20).map { |index| create_record("extra-#{index.to_s.rjust(2, '0')}", @queues.first) })
    { recordings: rows.transform_values { |record| { id: record.id.to_s, call_id: record.external_unique_id } },
      authorized_recording_count: 21, recording_provider_boundary: 'synthetic_in_memory_wav_not_external_homologation' }
  end

  private

  def create_rows
    {
      allowed: create_record('allowed', @queues.first), denied_unit: create_record('denied-unit', @queues.last),
      denied_tenant: create_record('denied-tenant', @queues.first, tenant: '9'),
      unmapped_provider: create_record('unmapped-provider', @queues.first, provider: 'jrc_pabx')
    }
  end

  def install_marker!(records)
    marker = { 'source_sha' => ENV.fetch('GITHUB_SHA'), 'nonce' => @nonce, 'record_ids' => records.map(&:id) }
    @account.update!(settings: @account.settings.merge(MARKER => marker))
  end

  def owned_environment!
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116' &&
            config.database == 'jrc_sd_bc_portal_concurrency_20261025_test' && config.configuration_hash[:host] == '127.0.0.1' &&
            ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' && @account.name.start_with?('SYNTHETIC pause ')
    owned &&= @account.name.end_with?('-recordings') && ENV.fetch('GITHUB_SHA').match?(/\A[0-9a-f]{40}\z/)
    raise 'Owned synthetic recording scope required' unless owned
  end

  def configure_roles
    @operator.custom_role.update!(permissions: RIGHTS + %w[jrc_contact_center_operate jrc_contact_center_recordings_download])
    @viewer.custom_role.update!(permissions: RIGHTS)
    @viewer.update!(role: :agent)
    JrcContactCenter::QueueMembership.create!(account: @account, queue: @queues.first, account_user: @viewer, active: true, role: 'agent')
  end

  def configure_native_history
    TelephonyIntegration.create!(account: @account, provider: 'hodupbx', history_enabled: false,
                                 cdr_base_url: 'https://pbx.example.test', cdr_api_version: 'v1.4', tenant_type: 'TENANT',
                                 pabx_username: 'synthetic-recordings', pabx_password: JrcContactCenter::SyntheticPassword.generate,
                                 pabx_settings: { enabled: true, provider: Pabx::Settings::PROVIDER, base_url: 'https://pbx.example.test',
                                                  expected_tenant: '8', sync_enabled: false, recording_lookup: 'link', timeout_seconds: 3 })
    [@operator, @viewer].each do |member|
      SipCredential.create!(account: @account, user: member.user, enabled: true, wss_server: 'wss://sip.example.test:7443',
                            sip_domain: 'sip.example.test', extension: '1410', call_history_extension: '1410',
                            username: "synthetic-#{member.id}", password: JrcContactCenter::SyntheticPassword.generate)
    end
  end

  def create_record(kind, queue, tenant: '8', provider: Pabx::Settings::PROVIDER)
    key = "synthetic-recording-#{@nonce}-#{kind}"
    first = 2.minutes.ago
    call = JrcContactCenter::CallSession.create!(account: @account, provider: provider, external_session_id: key, correlation_id: key,
                                                current_unit: queue.unit, current_queue: queue, direction: 'inbound', status: 'ended',
                                                started_at: first, answered_at: first + 1.second, ended_at: first + 61.seconds)
    create_participant_legs(call, queue)
    TelephonyCallRecord.create!(account: @account, provider: Pabx::Settings::PROVIDER, external_tenant: tenant, extension: '1410',
                               external_unique_id: key, started_at: first, synced_at: Time.current, direction: 'inbound', status: 'answered',
                               caller: '551100000001', callee: '1410', duration_seconds: 61, answered_seconds: 60,
                               has_recording: true, recording_reference: "/var/spool/asterisk/monitor/#{tenant}/synthetic-#{@nonce}.wav")
  end

  def create_participant_legs(call, queue)
    [@operator, @viewer].each do |member|
      JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: member, queue: queue, direction: 'inbound',
                                      status: 'ended', started_at: call.started_at, answered_at: call.answered_at, ended_at: call.ended_at)
    end
  end
end
