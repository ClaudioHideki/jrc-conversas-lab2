require 'rails_helper'

RSpec.describe Pabx::Sync, :pabx do
  let(:integration) { create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password') }
  let(:provider) { instance_double(Pabx::Provider) }
  let(:normalized) { Pabx::Contract.new(Pabx::Settings.new(integration)).normalize(pabx_row) }
  before do
    allow(Pabx::Provider).to receive(:new).with(integration).and_return(provider)
    allow(provider).to receive(:verify_scope!).and_return('accountcode' => '8')
    allow(provider).to receive(:call_history).and_return(total: 1, rows: [normalized])
  end

  it 'reprocesses a period idempotently and updates later status/recording availability' do
    2.times { described_class.new(integration).call }
    expect(TelephonyCallRecord.where(account: integration.account).count).to eq(1)
    allow(provider).to receive(:call_history).and_return(total: 1, rows: [normalized.merge(status: 'busy', has_recording: true, recording_reference: 'synthetic.wav')])
    described_class.new(integration).call
    expect(TelephonyCallRecord.find_by!(account: integration.account)).to have_attributes(status: 'busy', has_recording: true, recording_reference: 'synthetic.wav')
    expect(integration.reload.pabx_sync_state).to include('last_error' => nil, 'imported' => 1)
  end

  it 'reads all pages then advances the incremental cursor' do
    allow(provider).to receive(:call_history).and_return({ total: 2, rows: [normalized] },
      { total: 2, rows: [normalized.merge(external_unique_id: 'synthetic-call-2')] })
    expect { described_class.new(integration).call }.to change(TelephonyCallRecord, :count).by(2)
    expect(provider).to have_received(:call_history).with(hash_including(page: 2))
    expect(integration.reload.pabx_sync_state['cursor']).to be_present
  end

  it 'rolls back partial pages and does not advance cursor on repeated pages' do
    allow(provider).to receive(:call_history).and_return(total: 2, rows: [normalized])
    expect { described_class.new(integration).call }.to raise_error(Pabx::Error, 'REPEATED_PAGE')
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
    expect(integration.reload.pabx_sync_state).to include('last_error' => 'REPEATED_PAGE')
    expect(integration.pabx_sync_state).not_to have_key('cursor')
  end

  it 'blocks tenant mismatch before importing any call' do
    allow(provider).to receive(:verify_scope!).and_raise(Pabx::Error, 'TENANT_MISMATCH')
    expect { described_class.new(integration).call }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
    expect(provider).not_to have_received(:call_history)
    expect(TelephonyCallRecord.where(account: integration.account)).to be_empty
  end

  it 'does not connect when inactive and leaves SIP and legacy history independent' do
    integration.update!(pabx_settings: pabx_settings(enabled: false))
    expect(described_class.new(integration).call).to be_nil
    expect(provider).not_to have_received(:verify_scope!)
    expect(integration.reload.history_enabled?).to be(true)
  end

  it 'uses the configured overlap from the last successful cursor' do
    cursor = 10.minutes.ago.change(usec: 0)
    integration.update!(pabx_sync_state: { cursor: cursor.iso8601 })
    described_class.new(integration).call
    expect(provider).to have_received(:call_history).with(hash_including(from: cursor - 120.seconds))
  end

  it 'isolates uniqueId by Account and external tenant through the database index' do
    attributes = normalized.merge(provider: 'pabx_v1', external_tenant: '8', synced_at: Time.current)
    TelephonyCallRecord.create!(attributes.merge(account: integration.account))
    other = create(:account)
    expect { TelephonyCallRecord.create!(attributes.merge(account: other)) }.to change(TelephonyCallRecord, :count).by(1)
    expect { TelephonyCallRecord.create!(attributes.merge(account: integration.account, external_tenant: '12')) }.to change(TelephonyCallRecord, :count).by(1)
  end

  it 'does not enqueue duplicate scheduler/manual work in the configured interval' do
    integration
    scheduler = Pabx::ScheduleJob.new
    expect do
      expect(scheduler.enqueue(integration)).to be(true)
      expect(scheduler.enqueue(integration)).to be(false)
    end.to have_enqueued_job(Pabx::SyncJob).with(integration.account_id, integration.id).exactly(:once)
  end
end
