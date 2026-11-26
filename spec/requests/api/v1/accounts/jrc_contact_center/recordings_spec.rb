# frozen_string_literal: true

require 'rails_helper'

# Real authenticated HTTP/PostgreSQL scopes. Only the existing provider byte boundary is substituted.
RSpec.describe 'Control Desk recordings through both native scoped domains', :pabx, type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:rights) { %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen] }
  let(:role) { create(:custom_role, account: account, permissions: rights) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC recording issuer', relationship_type: 'internal') }
  let(:business) { account.jrc_crm_business_units.create!(operating_company: company, code: 'A', name: 'SYNTHETIC recording business unit') }
  let(:unit) do
    JrcContactCenter::Unit.create!(account: account, code: 'A', name: 'SYNTHETIC recording unit', kind: 'sac',
                                   settings: { issuer_company_id: company.id, business_unit_id: business.id })
  end
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'A', name: 'SYNTHETIC recording queue') }
  let(:integration) do
    create(:telephony_integration, account: account, pabx_settings: pabx_settings(recording_lookup: 'link', sync_enabled: false),
                                   pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:source_call) do
    JrcContactCenter::CallSession.create!(account: account, provider: Pabx::Settings::PROVIDER,
                                          external_session_id: 'synthetic-recorded-call', correlation_id: 'synthetic-recording-origin',
                                          current_unit: unit, current_queue: queue, direction: 'inbound', status: 'ended',
                                          started_at: 30.minutes.ago, ended_at: 29.minutes.ago)
  end
  let(:record) do
    TelephonyCallRecord.create!(account: account, provider: Pabx::Settings::PROVIDER, external_tenant: '8', extension: '1410',
                                external_unique_id: source_call.external_session_id, synced_at: Time.current,
                                started_at: source_call.started_at, direction: 'inbound', status: 'answered',
                                caller: '551100000001', callee: '1410', has_recording: true,
                                recording_reference: '/var/spool/asterisk/monitor/8/synthetic-test.wav')
  end
  let(:audio) { "RIFF#{[36].pack('V')}WAVEfmt #{[16, 1, 1, 8_000, 16_000, 2, 16].pack('VvvVVvv')}data#{[0].pack('V')}".b }

  def path
    "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings"
  end

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(role: :agent, custom_role: role)
    integration
    create(:sip_credential, account: account, user: actor, enabled: true, extension: '1410', call_history_extension: '1410')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company, business_unit: business,
                                                active: true, structure_managed: true)
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    JrcContactCenter::CallLeg.create!(account: account, call_session: source_call, account_user: member, queue: queue,
                                      direction: 'inbound', status: 'ended', started_at: source_call.started_at, ended_at: source_call.ended_at)
    record
    allow(Pabx::Client).to receive(:new) { raise 'External PABX client forbidden in native recording tests' }
  end

  it 'lists only an exact native provider and call identity with real scoped totals and private metadata' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.fetch('items').sole).to include('id' => record.id.to_s, 'call_session_id' => source_call.id.to_s,
                                                'unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s)
    expect(body.fetch('meta')).to include('page' => 1, 'per_page' => 20, 'total' => 1)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(response.body).not_to match(/recording_reference|synthetic-password|synthetic-user|service_url|metadata/)
  end

  it 'keeps an uncorrelated native recording unavailable without guessing from phone numbers' do
    source_call.update!(external_session_id: 'synthetic-other-identity')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get "#{path}/#{record.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not equate the proposed jrc_pabx adapter and the existing native recording provider' do
    source_call.update!(provider: 'jrc_pabx')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'retains own-extension authorization despite an exact permitted call identity' do
    record.update!(extension: '9999')
    get "#{path}/#{record.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not expose a same-queue call in which the ordinary viewer did not participate' do
    other = create(:user, account: account)
    source_call.legs.each { |leg| leg.update!(account_user_id: account.account_users.find_by!(user: other).id) }
    get "#{path}/#{record.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects a direct record in another native operational unit despite an existing personal leg' do
    other_business = account.jrc_crm_business_units.create!(operating_company: company, code: 'B', name: 'SYNTHETIC denied business unit')
    other_unit = JrcContactCenter::Unit.create!(account: account, code: 'B', name: 'SYNTHETIC denied recording unit', kind: 'sac',
                                                settings: { issuer_company_id: company.id, business_unit_id: other_business.id })
    source_call.update!(current_unit: other_unit)
    get "#{path}/#{record.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other_unit.name, record.external_unique_id)
  end

  it 'never borrows another account session or accepts caller account and user parameters as authority' do
    foreign = create(:user, account: create(:account))
    get "#{path}/#{record.id}", headers: foreign.create_new_auth_token, params: { account_id: account.id, user_id: actor.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects revoked view authority even when the URL and personal SIP extension are still known' do
    role.update!(permissions: ['jrc_contact_center_view'])
    get "#{path}/#{record.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'filters and pages before calculating scoped totals and restores the unfiltered authorized list' do
    get path, headers: headers, params: { q: 'synthetic-missing', unit_id: unit.id, queue_id: queue.id }
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
    get path, headers: headers, params: { page: 2, per_page: 1 }
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'total' => 1)
    get path, headers: headers
    expect(response.parsed_body.fetch('items').sole.fetch('id')).to eq(record.id.to_s)
  end

  it 'rejects an invalid period and unknown unit filters without silently widening the search' do
    get path, headers: headers, params: { from: '2026-02-30', to: '2026-03-01' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_recording_range')
    get path, headers: headers, params: { unit_id: 9_223_372_036_854_775_806 }
    expect(response).to have_http_status(:not_found)
  end

  it 'separates actual listening from download authority and records only safe native audit identifiers' do
    provider = instance_double(Pabx::Provider, recording: { body: audio, content_type: 'audio/wav' })
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    get "#{path}/#{record.id}/playback", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(audio)
    expect(response.headers['Content-Disposition']).to include('inline')
    audit = Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1').sole
    expect(audit.audited_changes).to include('operation' => 'listen', 'call_session_id' => source_call.id.to_s)
    expect(audit.audited_changes.to_json).not_to include('/var/spool', '551100000001', 'synthetic-password')
    get "#{path}/#{record.id}/download", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'downloads only with the independent native permission and preserves an audited exact byte identity' do
    role.update!(permissions: rights + ['jrc_contact_center_recordings_download'])
    provider = instance_double(Pabx::Provider, recording: { body: audio, content_type: 'audio/wav' })
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    get "#{path}/#{record.id}/download", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(audio)
    expect(response.headers['Content-Disposition']).to include('attachment')
    expect(response.headers).to include('X-Jrc-Recording-Account' => account.id.to_s, 'X-Jrc-Recording-Call' => source_call.id.to_s)
    audit = Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1').sole
    expect(audit.audited_changes.fetch('operation')).to eq('download')
  end

  it 'normalizes a natively permitted octet-stream WAV without exposing a generic or provider-controlled filename' do
    role.update!(permissions: rights + ['jrc_contact_center_recordings_download'])
    provider = instance_double(Pabx::Provider, recording: { body: audio, content_type: 'application/octet-stream' })
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    get "#{path}/#{record.id}/download", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('audio/wav')
    expect(response.body.b).to eq(audio)
    expect(response.headers['Content-Disposition']).to include("filename=\"call-#{record.id}.wav\"")
    expect(response.headers['Content-Disposition']).not_to include('/var/spool', 'synthetic-test')
  end

  it 'refuses unknown generic binary data without recording successful media access' do
    provider = instance_double(Pabx::Provider, recording: { body: 'SYNTHETIC invalid binary', content_type: 'application/octet-stream' })
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    get "#{path}/#{record.id}/playback", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('INVALID_RECORDING')
    expect(response.body).not_to include('SYNTHETIC invalid binary')
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1')).to be_empty
  end

  it 'rechecks a revoked permission after native provider I/O without disclosing bytes or recording successful access' do
    provider = instance_double(Pabx::Provider)
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    allow(provider).to receive(:recording) do
      role.update!(permissions: ['jrc_contact_center_view'])
      { body: audio, content_type: 'audio/wav' }
    end
    get "#{path}/#{record.id}/playback", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body.b).not_to eq(audio)
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1')).to be_empty
  end

  it 'does not disclose bytes after the native provider connection or credentials change during I/O' do
    provider = instance_double(Pabx::Provider)
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    allow(provider).to receive(:recording) do
      integration.update!(pabx_password: 'synthetic-replaced-password')
      { body: audio, content_type: 'audio/wav' }
    end
    get "#{path}/#{record.id}/playback", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('recording_source_changed')
    expect(response.body.b).not_to eq(audio)
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1')).to be_empty
  end

  it 'rechecks native corporate coverage after provider I/O rather than relying on an old authorized metadata read' do
    provider = instance_double(Pabx::Provider)
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    allow(provider).to receive(:recording) do
      account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
      { body: audio, content_type: 'audio/wav' }
    end
    get "#{path}/#{record.id}/playback", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body.b).not_to eq(audio)
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1')).to be_empty
  end

  it 'does not disclose bytes from a recording reference that changed during provider I/O' do
    provider = instance_double(Pabx::Provider)
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    allow(provider).to receive(:recording) do
      record.update!(recording_reference: 'SYNTHETIC replaced private reference')
      { body: audio, content_type: 'audio/wav' }
    end
    get "#{path}/#{record.id}/playback", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body.b).not_to eq(audio)
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_access_v1')).to be_empty
  end

  def playable_source_revision
    provider = instance_double(Pabx::Provider)
    expect(provider).to receive(:recording).once.and_return(body: audio, content_type: 'audio/wav')
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    get "#{path}/#{record.id}/playback", headers: headers
    response.headers.fetch('X-Jrc-Recording-Revision')
  end

  it 'records each native reproduction with current authority and reuses one receipt for an explicit retry key' do
    revision = playable_source_revision
    input = { source_revision: revision, request_id: SecureRandom.uuid }
    post "#{path}/#{record.id}/reproduce", headers: headers, params: input
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    post "#{path}/#{record.id}/reproduce", headers: headers, params: input
    expect(response.parsed_body).to eq(first)
    audits = Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_reproduction_v1')
    expect(audits.count).to eq(1)
    audit = audits.sole
    expect(audit.user).to eq(actor)
    expect(audit.audited_changes).to include('operation' => 'reproduce', 'call_session_id' => source_call.id.to_s)
    expect(audit.audited_changes.to_json).not_to include('/var/spool', '551100000001', 'synthetic-password')
  end

  it 'refuses a malformed reproduction key without creating a successful audit' do
    input = { source_revision: playable_source_revision, request_id: 'SYNTHETIC invalid audit key' }
    post "#{path}/#{record.id}/reproduce", headers: headers, params: input
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_recording_request')
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_reproduction_v1')).to be_empty
  end

  it 'refuses to log an old media source after its recording reference changed' do
    input = { source_revision: playable_source_revision, request_id: SecureRandom.uuid }
    record.update!(recording_reference: 'SYNTHETIC changed recording source')
    post "#{path}/#{record.id}/reproduce", headers: headers, params: input
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('recording_source_changed')
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_reproduction_v1')).to be_empty
  end

  it 'rechecks current listening authority for every reproduction instead of treating prior bytes as a grant' do
    input = { source_revision: playable_source_revision, request_id: SecureRandom.uuid }
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
    post "#{path}/#{record.id}/reproduce", headers: headers, params: input
    expect(response).to have_http_status(:unauthorized)
    expect(Audited.audit_class.where(auditable: record, comment: 'jrc_contact_center_recording_reproduction_v1')).to be_empty
  end
end
