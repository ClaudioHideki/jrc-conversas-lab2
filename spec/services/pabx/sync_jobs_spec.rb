require 'rails_helper'

RSpec.describe 'PABX existing job controls', :pabx do
  let(:integration) do
    create(:telephony_integration, pabx_settings: pabx_settings, pabx_username: 'synthetic-user', pabx_password: 'synthetic-password')
  end

  it 'does not schedule or connect when enabled and sync_enabled are false' do
    integration.update!(pabx_settings: pabx_settings(enabled: false, sync_enabled: false))
    original = integration.attributes
    expect(Pabx::Client).not_to receive(:new)
    expect { Pabx::SyncJob.perform_now(integration.account_id, integration.id) }.not_to have_enqueued_job(Pabx::SyncJob)
    expect(Pabx::ScheduleJob.new.enqueue(integration)).to be(false)
    expect(integration.reload.attributes).to eq(original)
  end

  it 'cannot run a queued integration ID through another Account' do
    foreign = create(:account)
    expect(Pabx::Sync).not_to receive(:new)
    Pabx::SyncJob.perform_now(foreign.id, integration.id)
  end

  %w[TIMEOUT UNAVAILABLE RATE_LIMITED PROVIDER_ERROR].each do |code|
    it "bounds and delays a retry for #{code} using the existing ActiveJob queue" do
      service = instance_double(Pabx::Sync)
      allow(Pabx::Sync).to receive(:new).and_return(service)
      allow(service).to receive(:call).and_raise(Pabx::Error, code)
      expect do
        Pabx::SyncJob.perform_now(integration.account_id, integration.id)
      end.to have_enqueued_job(Pabx::SyncJob).with(integration.account_id, integration.id).on_queue('low')
      job = enqueued_jobs.select { |entry| entry[:job] == Pabx::SyncJob }.last
      expect(job[:at]).to be >= 25.seconds.from_now.to_f
    end
  end

  it 'does not retry a tenant mismatch as if it were a temporary failure' do
    service = instance_double(Pabx::Sync)
    allow(Pabx::Sync).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise(Pabx::Error, 'TENANT_MISMATCH')
    expect do
      expect { Pabx::SyncJob.perform_now(integration.account_id, integration.id) }.to raise_error(Pabx::Error, 'TENANT_MISMATCH')
    end.not_to have_enqueued_job(Pabx::SyncJob)
  end

  it 'does not schedule another internal retry after the third execution' do
    service = instance_double(Pabx::Sync)
    allow(Pabx::Sync).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_raise(Pabx::Error, 'TIMEOUT')
    job = Pabx::SyncJob.new(integration.account_id, integration.id)
    job.executions = 2
    expect do
      expect { job.perform_now }.to raise_error(Pabx::Error, 'TIMEOUT')
    end.not_to have_enqueued_job(Pabx::SyncJob)
  end
end
