# frozen_string_literal: true

require_relative 'jrc_call_center_recording_task_seed'
require_relative 'jrc_call_center_recording_ticket_seed'

# Exclusive synthetic records for the existing native browser runner. Never imports a real CDR or issues a provider request.
class JrcContactCenter::SyntheticRecordingsSeed
  MARKER = 'jrc_cc_owned_recordings_fixture'
  RIGHTS = %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen].freeze

  def self.call(account:, operator:, viewer:, queues:)
    new(account, operator, viewer, queues).call
  end

  # One additional, explicitly opted-in disposable preflight database. Never
  # infer ownership from the name alone or broaden the default fixture scope.
  def self.owned_database?(config)
    expected = if ENV['JRC_CC_COMMITTED_RECORDING_FIXTURE'] == 'true'
                 'jrc_cc_recording_fixture_committed_test'
               else
                 'jrc_sd_bc_portal_concurrency_20261025_test'
               end
    config.database == expected && ApplicationRecord.connection.current_database == expected
  end

  def self.allowed_scenarios?(values, allowed)
    valid = values.is_a?(Array) && !values.empty? && (values - allowed).empty?
    valid && (ENV['JRC_CC_COMMITTED_RECORDING_FIXTURE'] != 'true' || values == ['recordings'])
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
    @account.enable_features!('jrc_customer_master')
    configure_roles
    configure_native_history
    rows = create_rows
    extras = (1..20).map { |index| create_record("extra-#{index.to_s.rjust(2, '0')}", @queues.first) }
    install_marker!(rows.values + extras)
    { recordings: rows.transform_values { |record| recording_identity(record) },
      authorized_recording_count: 21, recording_provider_boundary: 'synthetic_in_memory_wav_not_external_homologation',
      quality_history_record: recording_identity(extras.first), ending_context: owned_ending_context(extras.first),
      manual_task_destination: JrcContactCenter::SyntheticRecordingTaskSeed.call(account: @account, operator: @operator),
      manual_ticket_destination: JrcContactCenter::SyntheticRecordingTicketSeed.call(account: @account, operator: @operator, queue: @queues.first) }
  end

  private

  def recording_identity(record)
    { id: record.id.to_s, call_id: record.external_unique_id }
  end

  # Reuse the committed native lifecycle record. Capturing a baseline must never create, start, complete or replace ACW.
  def owned_ending_context(record)
    call = JrcContactCenter::CallSession.find_by!(account: @account, provider: record.provider,
                                                  external_session_id: record.external_unique_id)
    qualification = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @operator, call_session: call, channel: 'voice')
    { recording_id: record.id.to_s, call_id: record.external_unique_id, call_session_id: call.id.to_s,
      qualification_id: qualification.id.to_s, account_user_id: @operator.id.to_s }
  end

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
    runtime = [Rails.env.test?, ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted',
               ENV['GITHUB_REF_NAME'] == 'codex/call-center-control-desk-20261116',
               self.class.owned_database?(config), config.configuration_hash[:host] == '127.0.0.1',
               ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15', ENV.fetch('GITHUB_SHA', '').match?(/\A[0-9a-f]{40}\z/)].all?
    raise 'Owned synthetic recording scope required' unless runtime && owned_account?
  end

  def owned_account?
    @account&.name&.start_with?('SYNTHETIC pause ') && @account.name.end_with?('-recordings')
  end

  def configure_roles
    extra = %w[jrc_contact_center_operate jrc_contact_center_recordings_download jrc_contact_center_audit
               jrc_contact_center_quality_review contact_manage]
    @operator.custom_role.update!(permissions: RIGHTS + extra)
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
    link_native_customer!(call, queue) if kind == 'allowed'
    TelephonyCallRecord.create!(account: @account, provider: Pabx::Settings::PROVIDER, external_tenant: tenant, extension: '1410',
                                external_unique_id: key, started_at: first, synced_at: Time.current, direction: 'inbound', status: 'answered',
                                caller: '551100000001', callee: '1410', duration_seconds: 61, answered_seconds: 60,
                                has_recording: true, recording_reference: "/var/spool/asterisk/monitor/#{tenant}/synthetic-#{@nonce}.wav")
  end

  # Only this fixture's owned Account and explicitly scoped ordinary operator receive test data and the existing directory right.
  def link_native_customer!(call, queue)
    company = @account.master_companies.find(queue.unit.settings.fetch('issuer_company_id'))
    contact = Contact.create!(account: @account, company_id: company.id, name: 'SYNTHETIC linked recording customer')
    call.update!(contact_id: contact.id, company_id: company.id)
  end

  def create_participant_legs(call, queue)
    [@operator, @viewer].each do |member|
      JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: member, queue: queue, direction: 'inbound',
                                        status: 'ended', started_at: call.started_at, answered_at: call.answered_at, ended_at: call.ended_at)
    end
  end
end
