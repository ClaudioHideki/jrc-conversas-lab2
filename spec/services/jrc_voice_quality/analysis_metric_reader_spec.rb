# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcVoiceQuality::AnalysisMetricReader do
  let(:reader) { described_class.new }
  let(:cutoff) { Time.iso8601('2026-11-27T12:00:00Z') }
  let(:row) do
    { 'account_id' => 1, 'call_id' => 'synthetic-a', 'analise_id' => '9', 'analise_criada_em' => '2026-11-27T11:00:00Z',
      'sentimento_cliente' => 'positivo', 'sentimento_atendente' => 'neutro', 'nota_final' => 0 }
  end

  before do
    allow(reader).to receive(:configured?).and_return(true)
    allow(reader).to receive(:request) { raise 'Unspecified remote request is forbidden' }
  end

  def read(ids = ['synthetic-a'])
    reader.call(account_id: 1, call_ids: ids, observed_before: cutoff)
  end

  it 'reads only thin account-scoped metrics through the existing view and preserves the native zero score' do
    allow(reader).to receive(:request).with(:get, '/vw_qualidade_pabx_dashboard', any_args).and_return([row], [])
    expect(read.fetch('synthetic-a')).to eq(row)
    expect(reader).to have_received(:request).with(:get, '/vw_qualidade_pabx_dashboard',
                                                  hash_including(query: hash_including(account_id: 'eq.1', offset: 0,
                                                                                      select: described_class::FIELDS.join(','))))
    expect(described_class::FIELDS).not_to include('texto_transcrito', 'payload_completo', 'telefone_origem', 'arquivo_audio')
  end

  it 'continues after a server page shorter than the requested size instead of silently dropping later analyses' do
    later = row.merge('call_id' => 'synthetic-b', 'analise_id' => '10')
    allow(reader).to receive(:request).and_return([row], [later], [])
    expect(read(%w[synthetic-a synthetic-b]).keys).to eq(%w[synthetic-a synthetic-b])
    expect(reader).to have_received(:request).with(:get, anything, hash_including(query: hash_including(offset: 1)))
    expect(reader).to have_received(:request).with(:get, anything, hash_including(query: hash_including(offset: 2)))
  end

  it 'counts each native analysis only once even when the transcription join repeats it and selects the latest analysis' do
    older = row.merge('analise_id' => '8', 'analise_criada_em' => '2026-11-27T10:00:00Z', 'sentimento_cliente' => 'negativo')
    allow(reader).to receive(:request).and_return([older, row, row.dup], [])
    expect(read).to eq('synthetic-a' => row)
  end

  it 'uses numeric native identity order when two analyses have the same timestamp' do
    newer = row.merge('analise_id' => '10', 'sentimento_cliente' => 'neutro')
    allow(reader).to receive(:request).and_return([row, newer], [])
    expect(read.fetch('synthetic-a')).to eq(newer)
  end

  it 'rejects contradictory duplicates of the same analysis rather than choosing arbitrary content' do
    allow(reader).to receive(:request).and_return([row, row.merge('sentimento_cliente' => 'negativo')])
    expect { read }.to raise_error(JrcVoiceQuality::PersistenceError)
  end

  [
    { 'account_id' => 2 }, { 'call_id' => 'foreign-call' }, { 'analise_id' => nil }, { 'analise_criada_em' => 'invalid' },
    { 'analise_criada_em' => '2026-11-27T13:00:00Z' }, { 'texto_transcrito' => 'SYNTHETIC forbidden field' }
  ].each do |change|
    it "rejects unverified identity, cutoff or unexpected fields #{change.keys.inspect} without returning partial metrics" do
      allow(reader).to receive(:request).and_return([row.merge(change)])
      expect { read }.to raise_error(JrcVoiceQuality::PersistenceError)
    end
  end

  it 'returns a verified empty cohort without any network access, still validating the account' do
    expect(reader).not_to receive(:request)
    expect(read([])).to eq({})
    expect { reader.call(account_id: 'bad', call_ids: [], observed_before: cutoff) }.to raise_error(JrcVoiceQuality::PersistenceError)
  end

  it 'never represents an unconfigured source as an empty analysis result' do
    allow(reader).to receive(:configured?).and_return(false)
    expect { read }.to raise_error(JrcVoiceQuality::ConfigurationError)
    expect(reader).not_to have_received(:request)
  end

  it 'propagates native connectivity failures instead of treating them as zero analyses' do
    allow(reader).to receive(:request).and_raise(JrcVoiceQuality::PersistenceError.new('SYNTHETIC outage', code: :supabase_error))
    expect { read }.to raise_error(JrcVoiceQuality::PersistenceError, 'SYNTHETIC outage')
  end

  it 'turns an exhausted total I/O deadline into an unavailable result without returning accumulated partial metrics' do
    allow(reader).to receive(:request).and_raise(Timeout::Error)
    expect { read }.to raise_error(JrcVoiceQuality::PersistenceError)
  end

  it 'does not return partial results when the global row budget is exhausted' do
    stub_const('JrcVoiceQuality::AnalysisMetricReader::MAX_ROWS', 1)
    allow(reader).to receive(:request).and_return([row, row.dup])
    expect { read }.to raise_error(JrcVoiceQuality::PersistenceError)
  end

  it 'bounds the number of remote pages even when a provider never finishes the result' do
    stub_const('JrcVoiceQuality::AnalysisMetricReader::MAX_PAGES', 2)
    allow(reader).to receive(:request).and_return([row])
    expect { read }.to raise_error(JrcVoiceQuality::PersistenceError)
    expect(reader).to have_received(:request).exactly(2).times
  end

  it 'applies the remaining global deadline to native network I/O and refuses an expired final result' do
    allow(reader).to receive(:clock).and_return(0, 5, 6, 25)
    allow(reader).to receive(:request).and_return([row])
    expect { read }.to raise_error(JrcVoiceQuality::PersistenceError)
    expect(reader).to have_received(:request).with(:get, anything, hash_including(timeout: 18))
  end

  it 'rejects a cohort beyond the explicit limit before contacting the provider' do
    stub_const('JrcVoiceQuality::AnalysisMetricReader::MAX_CALLS', 1)
    expect { read(%w[synthetic-a synthetic-b]) }.to raise_error(JrcVoiceQuality::PersistenceError)
    expect(reader).not_to have_received(:request)
  end

  it 'batches ordinary identifiers without one request per call or dropping the final partial batch' do
    ids = Array.new(201) { |index| "synthetic-#{index}" }
    queries = []
    allow(reader).to receive(:request) do |_method, _path, **options|
      queries << options.fetch(:query).fetch(:call_id)
      []
    end
    expect(read(ids)).to eq({})
    batches = queries.map { |query| JSON.parse("[#{query.delete_prefix('in.(').delete_suffix(')')}]") }
    expect(batches.map(&:length)).to eq([100, 100, 1])
    expect(batches.flatten).to eq(ids)
  end

  it 'also bounds encoded query bytes for long legal native IDs without truncating or inventing identifiers' do
    ids = Array.new(20) { |index| ":#{':' * 250}#{index.to_s.rjust(3, '0')}" }
    queries = []
    allow(reader).to receive(:request) do |_method, _path, **options|
      queries << options.fetch(:query).fetch(:call_id)
      []
    end
    expect(read(ids)).to eq({})
    expect(queries.length).to be > 1
    expect(queries.map { |query| URI.encode_www_form_component(query).bytesize }).to all(be <= described_class::MAX_QUERY_ID_BYTES + 20)
    expect(queries.flat_map { |query| JSON.parse("[#{query.delete_prefix('in.(').delete_suffix(')')}]") }).to eq(ids)
  end

  it 'uses the remaining deadline in the unchanged native HTTP flow while retaining its legacy twenty-second default' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('SUPABASE_URL', '').and_return('https://synthetic.example.invalid')
    allow(ENV).to receive(:fetch).with('SUPABASE_SERVICE_ROLE_KEY', '').and_return('SYNTHETIC-test-value')
    allow(reader).to receive(:request).and_call_original
    allow(reader).to receive(:clock).and_return(0, 1, 2, 3, 4, 5, 6)
    responses = [[row], [], [row]]
    timeouts = []
    allow(HTTParty).to receive(:get) do |url, **options|
      expect(url).to eq('https://synthetic.example.invalid/rest/v1/vw_qualidade_pabx_dashboard')
      timeouts << options.fetch(:timeout)
      instance_double(HTTParty::Response, success?: true, body: JSON.generate(responses.shift))
    end
    expect(read.fetch('synthetic-a')).to eq(row)
    expect(JrcVoiceQuality::SupabaseClient.new.find_analysis(account_id: 1, call_id: 'synthetic-a')).to include(id: '9')
    expect(timeouts).to eq([20, 19, 20])
  end
end
