# frozen_string_literal: true

require 'rails_helper'

# Exercise the actual private transport. Only HTTP I/O is replaced; no vendor
# request, token, account policy or database is involved in these regressions.
RSpec.describe JrcVoiceQuality::SupabaseClient, '#request', :pabx do
  let(:client) { described_class.new }
  let(:reply) { instance_double(HTTParty::Response, success?: true, body: '[]') }

  around do |example|
    with_modified_env SUPABASE_URL: 'https://supabase.example.test', SUPABASE_SERVICE_ROLE_KEY: 'SYNTHETIC-transport-only' do
      example.run
    end
  end

  before do
    allow(HTTParty).to receive(:public_send).and_return(reply)
  end

  it 'preserves the native default query, body, headers and twenty-second timeout' do
    expect(client.send(:request, :get, '/SYNTHETIC-resource')).to eq([])
    expect(HTTParty).to have_received(:public_send).with(
      :get, 'https://supabase.example.test/rest/v1/SYNTHETIC-resource',
      query: {}, body: nil, headers: hash_including('apikey' => 'SYNTHETIC-transport-only'), timeout: 20
    )
  end

  it 'preserves scoped query, JSON body, custom headers and the original bounded analysis timeout' do
    query = { account_id: 'eq.42', call_id: 'eq.SYNTHETIC-call' }
    client.send(
      :request, :patch, '/SYNTHETIC-resource',
      query: query, body: { status: 'SYNTHETIC' }, headers: { 'Prefer' => 'return=minimal' }, timeout: 1.25
    )
    expect(HTTParty).to have_received(:public_send).with(
      :patch, 'https://supabase.example.test/rest/v1/SYNTHETIC-resource',
      query: query, body: { status: 'SYNTHETIC' }.to_json,
      headers: hash_including('Prefer' => 'return=minimal', 'apikey' => 'SYNTHETIC-transport-only'), timeout: 1.25
    )
  end

  it 'rejects unknown transport keywords before making any HTTP request' do
    expect { client.send(:request, :get, '/SYNTHETIC-resource', unknown: true) }.to raise_error(ArgumentError)
    expect(HTTParty).not_to have_received(:public_send)
  end
end
