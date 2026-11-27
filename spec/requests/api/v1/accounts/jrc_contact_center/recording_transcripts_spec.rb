# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native authorized original recording transcript', :pabx do
  include_context 'with native authorized quality review source'

  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/quality_review/transcript" }
  let(:headers) { actor.create_new_auth_token }
  let(:audit_rows) do
    Audited.audit_class.where(auditable: record, associated: account, comment: JrcContactCenter::RecordingAudit::COMMENTS.first)
  end

  it 'returns the unchanged original only after native authorization and writes a scoped metadata-only read receipt' do
    original = Marshal.load(Marshal.dump(analysis))
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => account.id.to_s, 'recording_id' => record.id.to_s,
                                            'call_session_id' => source_call.id.to_s, 'call_id' => record.external_unique_id,
                                            'text' => 'SYNTHETIC original transcript', 'segments' => [],
                                            'temporal_alignment' => 'not_supplied_by_native_source')
    expect(response.parsed_body.fetch('source_sha256')).to match(/\A[0-9a-f]{64}\z/)
    expect(response.headers.fetch('Cache-Control')).to include('private', 'no-store')
    expect(response.body).not_to include(record.recording_reference, 'synthetic-password')
    expect(analysis).to eq(original)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'keeps the read audit scoped and free of private transcript text without adding a human correction' do
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    audit = audit_rows.sole
    expect(audit.user_id).to eq(actor.id)
    expect(audit.audited_changes).to include('operation' => 'transcript', 'call_session_id' => source_call.id.to_s)
    expect(audit.audited_changes.fetch('cc_scope').fetch('after')).to include('unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s)
    expect(audit.audited_changes.to_json).not_to include('SYNTHETIC original transcript')
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end

  it 'requires listening authority independently of human-review or administrator status and never grants permissions' do
    role.update!(permissions: recording_rights)
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    member.update!(role: :administrator)
    role.update!(permissions: recording_rights - ['jrc_contact_center_recordings_listen'])
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC original transcript')
    expect(audit_rows.count).to eq(1)
  end

  it 'rejects foreign accounts and out-of-unit recordings before querying the remote analysis source' do
    expect(provider).not_to receive(:find_analysis)
    foreign = create(:account)
    get path.sub("accounts/#{account.id}", "accounts/#{foreign.id}"), headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC original transcript')
    account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('SYNTHETIC original transcript')
    expect(audit_rows).to be_empty
  end

  it 'revalidates current listening authority after analysis I/O and does not disclose the already fetched original' do
    allow(provider).to receive(:find_analysis) do
      role.update!(permissions: recording_rights - ['jrc_contact_center_recordings_listen'])
      analysis
    end
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC original transcript')
    expect(audit_rows).to be_empty
  end

  it 'distinguishes an absent transcript from malformed source data without manufacturing dialogue or timestamps' do
    allow(provider).to receive(:find_analysis).and_return(analysis.merge(texto_transcrito: nil))
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('text' => nil, 'segments' => [])
    allow(provider).to receive(:find_analysis).and_return(analysis.merge(texto_transcrito: ['SYNTHETIC malformed']))
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('quality_analysis_source_unavailable')
    expect(audit_rows.count).to eq(1)
  end

  it 'keeps source outages explicit and does not infer text from the reviewed summary or provider errors' do
    [JrcVoiceQuality::ConfigurationError, JrcVoiceQuality::PersistenceError].each do |error|
      allow(provider).to receive(:find_analysis).and_raise(error.new('SYNTHETIC private source configuration'))
      get path, headers: headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('error' => 'quality_analysis_source_unavailable')
      expect(response.body).not_to include('SYNTHETIC private source configuration')
    end
    expect(audit_rows).to be_empty
  end

  it 'reads the authorized original without fetching audio or creating provider commands when media is unavailable' do
    expect(Pabx::Client).not_to receive(:new)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
    get path, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('text')).to eq('SYNTHETIC original transcript')
    expect(response.parsed_body).not_to have_key('media_url')
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'fails closed before rendering transcript when PostgreSQL rejects its native read audit' do
    headers
    name = "cc_synthetic_transcript_audit_#{Integer(account.id)}"
    condition = "associated_id <> #{Integer(account.id)} OR COALESCE(audited_changes ->> 'operation', '') <> 'transcript'"
    ApplicationRecord.connection.add_check_constraint(:audits, condition, name: name)
    violations = []
    observer = lambda do |*args|
      failure = args.last[:exception_object]
      failure = failure.cause while failure && !failure.is_a?(PG::CheckViolation)
      violations << failure.result.error_field(PG::Result::PG_DIAG_CONSTRAINT_NAME) if failure
    end
    ActiveSupport::Notifications.subscribed(observer, 'sql.active_record') do
      expect do
        ApplicationRecord.transaction(requires_new: true) { get path, headers: headers, as: :json }
      end.to raise_error(ActiveRecord::StatementInvalid)
    end
    expect(violations).to eq([name])
    expect(audit_rows).to be_empty
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end
end
