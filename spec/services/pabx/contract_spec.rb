require 'rails_helper'

RSpec.describe Pabx::Contract, :pabx do
  let(:integration) { build(:telephony_integration, pabx_settings: pabx_settings) }
  let(:settings) { Pabx::Settings.new(integration) }
  let(:contract) { described_class.new(settings) }

  it 'accepts the documented empty result without claiming a populated CDR mapping' do
    integration.pabx_settings = pabx_settings.except('cdr_rows_path', 'cdr_fields')
    expect(contract.page('total' => 0, 'ramais' => [])).to eq(total: 0, rows: [])
  end

  it 'keeps a populated unknown schema pending instead of inventing fields' do
    integration.pabx_settings = pabx_settings.except('cdr_rows_path', 'cdr_fields')
    expect { described_class.new(Pabx::Settings.new(integration)).page('total' => 1, 'calls' => [pabx_row]) }
      .to raise_error(Pabx::Error, 'CDR_MAPPING_PENDING')
  end

  { 'IN' => 'inbound', 'OUT' => 'outbound', 'INTRA' => 'local', 'API' => 'api' }.each do |raw, expected|
    it "maps documented type #{raw} from the explicit synthetic field contract" do
      expect(contract.normalize(pabx_row(tipo: raw))).to include(direction: expected, extension: '1410', external_unique_id: 'synthetic-call-1')
    end
  end

  { 'ANSWERED' => 'answered', 'NO ANSWER' => 'unanswered', 'BUSY' => 'busy', 'CONGESTION' => 'congestion' }.each do |raw, expected|
    it "maps documented status #{raw}" do
      expect(contract.normalize(pabx_row(status: raw))[:status]).to eq(expected)
    end
  end

  it 'keeps missing durations unavailable instead of treating them as zero' do
    expect(contract.normalize(pabx_row.except('duration', 'billsec'))).to include(duration_seconds: nil, answered_seconds: nil)
  end

  ['S', 'N'].each do |flag|
    it "maps recording availability #{flag}" do
      expect(contract.normalize(pabx_row(gravacao: flag))[:has_recording]).to eq(flag == 'S')
    end
  end

  it 'blocks a mismatched row even after a matching dashboard' do
    expect { contract.page('total' => 1, 'calls' => [pabx_row(accountcode: '12')]) }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
  end

  it 'does not accept traversal or Asterisk paths as opaque recording references' do
    expect(contract.normalize(pabx_row(recording_id: '../../etc/passwd'))[:recording_reference]).to be_nil
    expect(contract.normalize(pabx_row(recording_id: '/var/spool/asterisk/a.wav'))[:recording_reference]).to be_nil
  end

  [nil, '', 'not-a-time'].each do |value|
    it "does not invent a timestamp for #{value.inspect}" do
      expect { contract.normalize(pabx_row(started_at: value)) }.to raise_error(Pabx::Error, 'INVALID_CDR_TIME')
    end
  end

  it 'isolates technical prefix conversion in the provider settings' do
    expect(settings.identity('1410')).to eq('81410')
    integration.pabx_settings['technical_identity'] = 'plain'
    expect(settings.identity('1410')).to eq('1410')
  end
end
