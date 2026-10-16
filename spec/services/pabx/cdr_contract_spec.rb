require 'rails_helper'

RSpec.describe 'CDR documented transport and explicit mapping', :pabx do
  let(:integration) do
    create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end
  let(:contract) { Pabx::Contract.new(Pabx::Settings.new(integration)) }
  let(:dashboard) { { accountcode: '8' } }
  before do
    allow(Resolv).to receive(:getaddresses).with('pbx.example.test').and_return(['93.184.216.34'])
    stub_request(:post, 'https://pbx.example.test/api/v1/auth/login').to_return(body: { token: 'synthetic-token' }.to_json)
    stub_request(:get, 'https://pbx.example.test/api/v1/admin/dashboard-extension').to_return { { body: dashboard.to_json } }
  end

  it 'parses the documented empty envelope without configuring a fabricated row schema' do
    integration.pabx_settings = { 'expected_tenant' => '8' }
    expect(contract.page('resultado' => { 'current_page' => 1, 'data' => [] }, 'data' => { 'total' => 0 }))
      .to eq(total: 0, rows: [])
  end

  it 'does not convert technical identifiers without an explicit CDR identity contract' do
    integration.pabx_settings = pabx_settings.except('cdr_extension_identity')
    expect(contract.normalize(pabx_row)[:extension]).to eq('81410')
    expect(contract.normalize(pabx_row(ramal: '1410'))[:extension]).to eq('1410')
    expect(Pabx::Settings.new(integration).identity('1410')).to eq('81410')
  end

  it 'applies only the explicitly configured CDR prefix rule and does not mutate input data' do
    row = pabx_row.freeze
    expect(contract.normalize(row)[:extension]).to eq('1410')
    expect(row['ramal']).to eq('81410')
    expect { contract.normalize(pabx_row(ramal: '1410')) }.to raise_error(Pabx::Error, 'INVALID_EXTENSION')
  end

  ['2026-10-15', '2026-10-15T08:00:00', 'not-a-time'].each do |raw|
    it "rejects ambiguous or invalid timestamp #{raw}" do
      expect { contract.normalize(pabx_row(started_at: raw)) }.to raise_error(Pabx::Error, 'INVALID_CDR_TIME')
    end
  end

  it 'conserves timestamps and nullable durations rather than inventing elapsed seconds' do
    row = contract.normalize(pabx_row(started_at: '2026-10-15T08:00:00-03:00').except('duration', 'billsec'))
    expect(row[:started_at].utc.iso8601).to eq('2026-10-15T11:00:00Z')
    expect(row.values_at(:duration_seconds, :answered_seconds)).to eq([nil, nil])
  end

  it 'rejects more rows than the declared total' do
    expect { contract.page('total' => 0, 'calls' => [pabx_row]) }.to raise_error(Pabx::Error, 'INVALID_PAGINATION')
  end

  it 'blocks CDR requests on tenant mismatch before querying calls' do
    dashboard[:accountcode] = '12'
    expect do
      Pabx::Provider.new(integration).call_history(from: 1.hour.ago, to: Time.current, page: 1)
    end.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
    expect(a_request(:post, %r{/relatorio-cdr/search})).not_to have_been_made
  end

  it 'uses documented per-page quantity and blocks undocumented continuation by default' do
    integration.pabx_settings = pabx_settings.except('cdr_page_parameter')
    request = stub_request(:post, 'https://pbx.example.test/api/v1/admin/relatorio-cdr/search')
              .with(body: hash_including('paginacao' => 20)).to_return(body: { total: 0 }.to_json)
    provider = Pabx::Provider.new(integration)
    provider.call_history(from: 1.hour.ago, to: Time.current, page: 1)
    expect(request).to have_been_requested.once
    expect { provider.call_history(from: 1.hour.ago, to: Time.current, page: 2) }
      .to raise_error(Pabx::Error, 'CDR_PAGINATION_PENDING')
  end
end
