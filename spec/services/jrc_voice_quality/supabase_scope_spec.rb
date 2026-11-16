require 'rails_helper'

RSpec.describe JrcVoiceQuality::SupabaseClient do
  let(:client) { described_class.new }
  let(:url) { 'https://quality.example.test/rest/v1' }
  around { |example| with_modified_env('SUPABASE_URL' => 'https://quality.example.test', 'SUPABASE_SERVICE_ROLE_KEY' => 'synthetic-only') { example.run } }

  it 'queries the same external identifier independently in two Accounts' do
    [11, 22].each do |id|
      request = stub_request(:get, "#{url}/vw_qualidade_pabx_dashboard")
                .with(query: hash_including('account_id' => "eq.#{id}", 'call_id' => 'eq.same-call'))
                .to_return(body: [{ account_id: id, call_id: 'same-call', analise_id: id }].to_json)
      expect(client.find_analysis(account_id: id, call_id: 'same-call')[:id]).to eq(id)
      expect(request).to have_been_requested.once
    end
  end

  it 'rejects a foreign or unscoped response even when the transport returns success' do
    stub_request(:get, "#{url}/vw_qualidade_pabx_dashboard").with(query: hash_including('account_id' => 'eq.11'))
      .to_return(body: [{ account_id: 22, call_id: 'same-call' }].to_json)
    expect { client.find_analysis(account_id: 11, call_id: 'same-call') }
      .to raise_error(JrcVoiceQuality::PersistenceError) { |error| expect(error.code).to eq(:scope_unverified) }
  end

  it 'includes account scope in batch lookups and does not fall back to an unscoped query' do
    request = stub_request(:get, "#{url}/vw_qualidade_pabx_dashboard")
              .with(query: hash_including('account_id' => 'eq.11')).to_return(status: 400, body: 'private-provider-payload')
    expect(Rails.logger).not_to receive(:warn).with(include('private-provider-payload'))
    expect(client.find_analyses_by_call_ids(account_id: 11, call_ids: ['same-call'])).to eq({})
    expect(request).to have_been_requested.once
  end

  it 'preserves scope on creation and never reuses another Account call' do
    stub_request(:get, "#{url}/chamadas_pabx").with(query: hash_including('account_id' => 'eq.11')).to_return(body: '[]')
    request = stub_request(:post, "#{url}/chamadas_pabx").with(body: hash_including('account_id' => 11, 'call_id' => 'same-call'))
              .to_return(body: [{ id: 'a1-b2', account_id: 11, call_id: 'same-call' }].to_json)
    expect(client.upsert_call!(account_id: 11, call_id: 'same-call')['id']).to eq('a1-b2')
    expect(request).to have_been_requested.once
  end

  it 'refuses a transcription for a parent outside the Account before writing' do
    stub_request(:get, "#{url}/chamadas_pabx").with(query: hash_including('account_id' => 'eq.11', 'id' => 'eq.a1-b2')).to_return(body: '[]')
    expect { client.save_transcription!(account_id: 11, chamada_id: 'a1-b2', text: 'synthetic', model: 'test') }
      .to raise_error(JrcVoiceQuality::PersistenceError)
    expect(a_request(:post, "#{url}/transcricoes_pabx")).not_to have_been_made
  end

  it 'scopes status updates and transcript writes even for UUID parent identifiers' do
    stub_request(:get, "#{url}/chamadas_pabx").with(query: hash_including('account_id' => 'eq.11', 'id' => 'eq.a1-b2'))
      .to_return(body: [{ id: 'a1-b2', account_id: 11 }].to_json)
    update = stub_request(:patch, "#{url}/chamadas_pabx").with(query: { 'account_id' => 'eq.11', 'id' => 'eq.a1-b2' }).to_return(body: '')
    transcript = stub_request(:post, "#{url}/transcricoes_pabx").with(body: hash_including('account_id' => 11, 'chamada_id' => 'a1-b2')).to_return(body: '')
    client.update_call_status!(account_id: 11, chamada_id: 'a1-b2', status: 'erro')
    client.save_transcription!(account_id: 11, chamada_id: 'a1-b2', text: 'synthetic', model: 'test')
    expect(update).to have_been_requested.once
    expect(transcript).to have_been_requested.once
  end
end
