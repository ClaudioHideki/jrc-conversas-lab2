# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe 'Native recording metadata CSV with current authority and unchanged recording filters', :pabx, type: :request do
  include_context 'with native authorized quality review source'

  let(:role) do
    create(:custom_role, account: account,
                         permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_reports])
  end
  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/reports/recordings/export" }
  let(:rows) { CSV.parse(response.body) }
  let(:another_record) do
    another_call = source_call.dup
    another_call.update!(external_session_id: 'SYNTHETIC-second-recording', correlation_id: 'SYNTHETIC-second-origin')
    leg = JrcContactCenter::CallLeg.where(call_session: source_call).sole.dup
    leg.update!(call_session: another_call)
    other = record.dup
    other.update!(external_unique_id: another_call.external_session_id, caller: 'SYNTHETIC-second-number')
    other
  end

  before do
    account.enable_features!('audit_logs')
    expect(Pabx::Provider).not_to receive(:new)
    expect(JrcVoiceQuality::SupabaseClient).not_to receive(:new)
  end

  it 'exports only authorized native metadata with matching identity, digest and redacted read audit' do
    integration.update!(pabx_username: 'SYNTHETIC-private-export-username')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    observed = %w[X-Jrc-Recording-Account X-Jrc-Recording-Count X-Content-SHA256].map { |key| response.headers[key] }
    expect(observed).to eq([account.id.to_s, '1', Digest::SHA256.hexdigest(response.body)])
    expect(rows.drop(1).map(&:first)).to eq([record.id.to_s])
    expect(response.body).not_to include(record.recording_reference, 'synthetic-password', 'SYNTHETIC-private-export-username')
    audit = Audited.audit_class.where(auditable: account, action: 'read').last
    expect(audit.audited_changes).to include('operation' => 'export', 'format' => 'csv', 'record_ids' => [record.id.to_s],
                                            'record_count' => 1, 'sha256' => Digest::SHA256.hexdigest(response.body))
    expect([audit.user_id, audit.request_uuid.present?]).to eq([actor.id, true])
    expect([JrcContactCenter::Command.where(account: account).count, source_call.reload.status]).to eq([0, 'ended'])
  end

  it 'keeps the authenticated report private and prevents content type sniffing' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('text/csv', 'charset=utf-8')
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(response.headers['Pragma']).to eq('no-cache')
    expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    expect(response.headers['Content-Disposition']).to include('attachment', 'call-center-gravacoes-')
  end

  it 'exports the entire bounded authorized query rather than silently exporting the visible page' do
    another_record
    get path, headers: headers, params: { page: '2', per_page: '1' }
    expect(response).to have_http_status(:ok)
    expect(rows.drop(1).map(&:first)).to contain_exactly(record.id.to_s, another_record.id.to_s)
    expect(response.headers['X-Jrc-Recording-Count']).to eq('2')
  end

  it 'uses the same native period, unit, queue, direction, result and search criteria as the list' do
    another_record
    criteria = { from: source_call.started_at.to_date.iso8601, to: source_call.started_at.to_date.iso8601,
                 unit_id: unit.id.to_s, queue_id: queue.id.to_s, status: 'answered', direction: 'inbound', q: record.external_unique_id }
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings", headers: headers, params: criteria
    expect(response).to have_http_status(:ok)
    visible = response.parsed_body.fetch('items').pluck('id')
    get path, headers: headers, params: criteria
    expect(response).to have_http_status(:ok)
    expect(rows.drop(1).map(&:first)).to eq(visible)
    expect(visible).to eq([record.id.to_s])
  end

  it 'returns a genuine empty report with its header and zero observed records' do
    get path, headers: headers, params: { direction: 'outbound' }
    expect(response).to have_http_status(:ok)
    expect(rows.length).to eq(1)
    expect(response.headers['X-Jrc-Recording-Count']).to eq('0')
    expect(response.headers['X-Content-SHA256']).to eq(Digest::SHA256.hexdigest(response.body))
  end

  it 'reuses native spreadsheet formula protection without changing stored metadata' do
    unit.update!(name: '=SYNTHETIC_FORMULA()')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(rows.fetch(1).fetch(3)).to eq("'=SYNTHETIC_FORMULA()")
    expect(unit.reload.name).to eq('=SYNTHETIC_FORMULA()')
  end

  [nil, 0].each do |duration|
    it "keeps a native #{duration.inspect} duration distinct from an invented measurement" do
      record.update!(duration_seconds: duration)
      get path, headers: headers
      expect(response).to have_http_status(:ok)
      expect(rows.fetch(1).last).to eq(duration.nil? ? nil : '0')
    end
  end

  %w[jrc_contact_center_reports jrc_contact_center_recordings_view].each do |right|
    it "rejects current withdrawal of #{right} before disclosing an export or adding its audit" do
      get path, headers: headers
      expect(response).to have_http_status(:ok)
      count = Audited.audit_class.where(auditable: account, action: 'read').count
      role.update!(permissions: role.permissions - [right])
      get path, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['X-Content-SHA256']).to be_nil
      expect(Audited.audit_class.where(auditable: account, action: 'read').count).to eq(count)
    end
  end

  it 'does not grant recording visibility from the native administrator report fallback' do
    member.update!(role: :administrator, custom_role: nil)
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(record.external_unique_id)
  end

  it 'does not present a disabled native history connection as a successful empty export' do
    integration.update!(pabx_settings: integration.pabx_settings.merge('enabled' => false))
    get path, headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch('error')).to eq('recording_export_unavailable')
    expect(response.headers['X-Content-SHA256']).to be_nil
    expect(Audited.audit_class.where(auditable: account, action: 'read')).to be_empty
  end

  it 'fails closed for the actual native tenant-mismatch state without exposing provider details' do
    integration.update!(pabx_sync_state: { 'last_error' => 'TENANT_MISMATCH' })
    get path, headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch('error')).to eq('recording_export_unavailable')
    expect(response.body).not_to include(record.external_unique_id, 'TENANT_MISMATCH', 'synthetic-password')
    expect(Audited.audit_class.where(auditable: account, action: 'read')).to be_empty
  end

  it 'does not disclose a foreign account recording that happens to share the external call identifier' do
    hidden = record.dup
    hidden.update!(account: create(:account), caller: 'SYNTHETIC-FOREIGN-PRIVATE')
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(rows.drop(1).map(&:first)).to eq([record.id.to_s])
    expect(response.body).not_to include('SYNTHETIC-FOREIGN-PRIVATE')
  end

  it 'denies a foreign corporate unit identifier instead of widening the report to all units' do
    business_b = account.jrc_crm_business_units.create!(operating_company: company, code: 'B', name: 'SYNTHETIC other business')
    hidden = JrcContactCenter::Unit.create!(account: account, code: 'B', name: 'SYNTHETIC private unit', kind: 'sac',
                                            settings: { issuer_company_id: company.id, business_unit_id: business_b.id })
    get path, headers: headers, params: { unit_id: hidden.id.to_s }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name, record.external_unique_id)
    expect(response.headers['X-Content-SHA256']).to be_nil
  end

  [
    { status: %w[answered unanswered] }, { direction: { value: 'inbound' } },
    { unit_id: ['1'] }, { queue_id: { value: '1' } },
    { from: 'not-a-date' }, { from: '2026-01-01', to: '2026-03-01' }
  ].each do |criteria|
    it "fails closed for malformed export criteria #{criteria.inspect} without a partial CSV" do
      get path, headers: headers, params: criteria
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.headers['X-Content-SHA256']).to be_nil
      expect(response.body).not_to include(record.external_unique_id)
      expect(Audited.audit_class.where(auditable: account, action: 'read')).to be_empty
    end
  end

  it 'rejects an over-limit query atomically before generating bytes or recording a successful export' do
    expect(Api::V1::Accounts::JrcContactCenter::ReportsController::RECORDING_EXPORT_MAX_ROWS).to eq(1000)
    another_record
    # Small native branch test only; the production 1000-row bound requires the
    # existing owned 5000-record native HTTP cohort, without creating another one.
    stub_const('Api::V1::Accounts::JrcContactCenter::ReportsController::RECORDING_EXPORT_MAX_ROWS', 1)
    get path, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('recording_export_limit_exceeded')
    expect(response.headers['X-Content-SHA256']).to be_nil
    expect(Audited.audit_class.where(auditable: account, action: 'read')).to be_empty
  end
end
