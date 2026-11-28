# frozen_string_literal: true

require 'rails_helper'

# Real HTTP, PostgreSQL, personal PABX and corporate scopes. Only the remote
# metric read is substituted, never authority, native SQL or persisted audits.
RSpec.describe 'Control Desk complete scoped original quality report', :pabx, type: :request do
  include_context 'with native authorized quality review source'

  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/quality_report" }
  let(:metric_reader) { instance_double(JrcVoiceQuality::AnalysisMetricReader) }
  let(:metric_rows) { {} }

  def metric_row(call_id, sentiment: 'positivo', score: 0)
    { 'account_id' => account.id, 'call_id' => call_id, 'analise_id' => "SYNTHETIC-#{call_id}",
      'analise_criada_em' => 1.minute.ago.iso8601(6), 'sentimento_cliente' => sentiment, 'sentimento_atendente' => nil, 'nota_final' => score }
  end

  def another_record(index, target_queue = queue)
    call = source_call.dup
    call.assign_attributes(external_session_id: "SYNTHETIC-quality-#{index}", correlation_id: "SYNTHETIC-quality-origin-#{index}",
                           current_queue: target_queue)
    call.save!
    leg = source_call.legs.first.dup
    leg.call_session = call
    leg.queue = target_queue
    leg.save!
    copy = record.dup
    copy.external_unique_id = call.external_session_id
    copy.save!
    copy
  end

  # Actual model validations and native callbacks remain enabled; source I/O
  # alone is substituted. This is read-scale QA, not provider throughput proof.
  def scale_cohort(size)
    size.times { |index| another_record("scale-#{index}") }
  end

  before do
    allow(JrcVoiceQuality::AnalysisMetricReader).to receive(:new).and_return(metric_reader)
    allow(metric_reader).to receive(:call) { |**arguments| metric_rows.slice(*arguments.fetch(:call_ids)) }
    metric_rows[record.external_unique_id] = metric_row(record.external_unique_id)
  end

  it 'uses the complete native period before pagination and keeps a zero quality score distinct from missing analyses' do
    21.times do |index|
      additional = another_record(index)
      metric_rows[additional.external_unique_id] = metric_row(additional.external_unique_id, sentiment: 'negativo', score: 80) if index < 20
    end
    get path, headers: headers, params: { per_page: 2, page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').length).to eq(2)
    expect(response.parsed_body.fetch('meta')).to include('total' => 22, 'page' => 2, 'pages' => 11)
    expect(response.parsed_body.fetch('quality_summary')).to include(
      'universe' => 22, 'analyzed' => 21, 'without_analysis' => 1,
      'counts' => { 'positivo' => 1, 'negativo' => 20, 'neutro' => 0 }
    )
    expect(metric_reader).to have_received(:call).with(account_id: account.id, call_ids: array_including(record.external_unique_id),
                                                       observed_before: a_kind_of(Time))
  end

  it 'uses one filtered universe for counts, segment selection, pagination and the native details identity' do
    negative = another_record(1)
    metric_rows[negative.external_unique_id] = metric_row(negative.external_unique_id, sentiment: 'negativo', score: 80)
    get path, headers: headers, params: { sentiment: 'negativo', status: 'answered', direction: 'inbound' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include(
      'id' => negative.id.to_s, 'unique_id' => negative.external_unique_id,
      'quality' => hash_including('sentiment' => 'negativo', 'quality_score' => 80)
    )
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    expect(response.parsed_body.dig('quality_summary', 'analyzed')).to eq(2)
    expect(response.parsed_body.dig('quality_summary', 'percentages', 'negativo')).to eq(50.0)
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
  end

  it 'proves the complete five-thousand-row native cohort without replacing the denominator with a twenty-row page',
     :cc_owned_quality_scale do
    scale_cohort(4_999)
    get path, headers: headers, params: { page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').length).to eq(20)
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'total' => 5_000, 'pages' => 250)
    expect(response.parsed_body.fetch('quality_summary')).to include('universe' => 5_000, 'analyzed' => 1, 'without_analysis' => 4_999)
  end

  it 'recalculates both the actual table and sentiment percentages for each authorized native queue' do
    second_queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'QUALITY-B', name: 'SYNTHETIC other quality queue')
    JrcContactCenter::QueueMembership.create!(account: account, queue: second_queue, account_user: member)
    negative = another_record(1, second_queue)
    metric_rows[negative.external_unique_id] = metric_row(negative.external_unique_id, sentiment: 'negativo')
    get path, headers: headers, params: { queue_id: queue.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('quality_summary')).to include(
      'universe' => 1, 'analyzed' => 1,
      'percentages' => { 'positivo' => 100.0, 'neutro' => 0.0, 'negativo' => 0.0 }
    )
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([record.id.to_s])
    get path, headers: headers, params: { queue_id: second_queue.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('quality_summary')).to include(
      'universe' => 1, 'analyzed' => 1,
      'percentages' => { 'positivo' => 0.0, 'neutro' => 0.0, 'negativo' => 100.0 }
    )
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([negative.id.to_s])
  end

  it 'does not infer positive or neutral when the configured source returned no analysis for an authorized call' do
    metric_rows.clear
    get path, headers: headers, params: { sentiment: 'without_analysis' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('quality_summary')).to include(
      'analyzed' => 0, 'without_analysis' => 1, 'quality_average' => nil,
      'percentages' => { 'positivo' => nil, 'neutro' => nil, 'negativo' => nil }
    )
    expect(response.parsed_body.fetch('items').sole.fetch('quality')).to eq('available' => false, 'sentiment' => nil, 'quality_score' => nil)
  end

  it 'passes an explicitly empty verified cohort after native result filtering without widening the universe' do
    get path, headers: headers, params: { direction: 'outbound' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('quality_summary', 'universe')).to eq(0)
    expect(metric_reader).to have_received(:call).with(account_id: account.id, call_ids: [], observed_before: a_kind_of(Time))
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'requires current independent recording-listen authority without an administrator fallback' do
    member.update!(role: :administrator)
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(metric_reader).not_to have_received(:call)
    expect(response.body).not_to include(record.external_unique_id)
  end

  it 'rejects an authenticated user in another account despite supplied account, user, unit or provider identifiers' do
    foreign = create(:user, account: create(:account))
    get path, headers: foreign.create_new_auth_token, params: { user_id: actor.id, unit_id: unit.id, call_id: record.external_unique_id }
    expect(response).to have_http_status(:unauthorized)
    expect(metric_reader).not_to have_received(:call)
    expect(response.body).not_to include(record.external_unique_id)
  end

  it 'withdraws the entire report when listening permission is revoked during provider I/O' do
    allow(metric_reader).to receive(:call) do
      role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
      metric_rows
    end
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('quality_summary')
    expect(response.body).not_to include(record.external_unique_id)
  end

  it 'withdraws the entire report when corporate coverage disappears during provider I/O' do
    allow(metric_reader).to receive(:call) do
      account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
      metric_rows
    end
    get path, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).not_to have_key('items')
    expect(response.body).not_to include(record.external_unique_id)
  end

  it 'does not replace the authenticated actor with a different currently eligible user after membership reassignment during I/O' do
    allow(metric_reader).to receive(:call) do
      reassign_native_quality_member!
      metric_rows
    end
    get path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('quality_summary')
    expect(response.body).not_to include(record.external_unique_id)
  end

  it 'reports a source conflict when a recording or the native connection is replaced during provider I/O' do
    allow(metric_reader).to receive(:call) do
      integration.update!(pabx_password: 'SYNTHETIC-replaced-password')
      record.update!(synced_at: 1.second.from_now)
      metric_rows
    end
    get path, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('quality_summary_source_changed')
    expect(response.body).not_to include(record.external_unique_id, 'SYNTHETIC-replaced-password')
  end

  it 'leaves the native authority block before external I/O and never exposes credentials or transcripts' do
    inside_authority = false
    allow(JrcContactCenter::AuthorityTransaction).to receive(:call).and_wrap_original do |original, **options, &block|
      inside_authority = true
      original.call(**options, &block)
    ensure
      inside_authority = false
    end
    allow(metric_reader).to receive(:call) do
      expect(inside_authority).to be(false)
      metric_rows
    end
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to match(/payload_completo|texto_transcrito|recording_reference|pabx_password|service_role|analise_id/)
  end

  it 'returns an explicit unavailable response without a fabricated successful zero when the source fails' do
    allow(metric_reader).to receive(:call).and_raise(JrcVoiceQuality::PersistenceError.new('SYNTHETIC outage', code: :supabase_error))
    get path, headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).not_to have_key('quality_summary')
    expect(response.body).not_to include('SYNTHETIC outage')
  end

  it 'refuses an over-limit cohort without contacting the source or returning a truncated sample' do
    stub_const('JrcContactCenter::RecordingQualityReport::MAX_RECORDS', 1)
    another_record(1)
    get path, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('quality_summary_range_too_large')
    expect(metric_reader).not_to have_received(:call)
    expect(response.parsed_body).not_to have_key('items')
  end

  it 'records a scoped read audit without copying the analysis body or source identifiers into the audit' do
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    audit = Audited.audit_class.where(associated: account, comment: 'jrc_contact_center_recording_access_v1').order(:id).last
    expect(audit.audited_changes).to include('operation' => 'quality_summary', 'record_ids' => [record.id.to_s])
    expect(audit.audited_changes.to_json).not_to include(record.external_unique_id, 'sentimento_cliente', 'nota_final')
  end

  [{ sentiment: 'critical' }, { sentiment: %w[positivo negativo] }, { sentiment: { value: 'positivo' } },
   { from: '2026-11-01', to: '2026-10-01' }, { status: 'arbitrary' }].each do |criteria|
    it "rejects invalid native report filters #{criteria.inspect} before provider I/O" do
      get path, headers: headers, params: criteria
      expect(response).to have_http_status(:unprocessable_entity)
      expect(metric_reader).not_to have_received(:call)
      expect(response.parsed_body).not_to have_key('quality_summary')
    end
  end
end
