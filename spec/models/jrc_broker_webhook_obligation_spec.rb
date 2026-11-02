require 'rails_helper'

RSpec.describe 'Durable Broker message obligation', type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:binding) do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end
  let(:message) { build(:message, account: account, inbox: inbox, message_type: :outgoing) }

  it 'keeps the message and its obligation when dispatch after COMMIT fails' do
    allow(message).to receive(:dispatch_create_events).and_raise('synthetic process boundary')
    expect { message.save! }.to raise_error('synthetic process boundary')
    expect(Message.exists?(message.id)).to be(true)
    expect(JrcBrokerWebhookObligation.find_by!(message_id: message.id).state).to eq('pending')
  end

  it 'rolls back the obligation with the message' do
    Message.transaction do
      message.save!
      raise ActiveRecord::Rollback
    end
    expect(JrcBrokerWebhookObligation.where(message_id: message.id)).to be_empty
  end

  it 'recovers Broker downtime with the same delivery identity and ignores duplicate jobs' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    delivery_ids = []
    allow(SafeFetch).to receive(:fetch) do |_url, **options|
      delivery_ids << options.fetch(:headers).fetch('X-Chatwoot-Delivery')
      raise Errno::ECONNREFUSED if delivery_ids.one?
    end
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('pending')
    travel 20.minutes do
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    end
    expect(obligation.reload.state).to eq('delivered')
    expect(delivery_ids).to eq([obligation.delivery_id, obligation.delivery_id])
  end

  it 'rejects a replaced binding instead of sending the old message' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    binding.update!(instance_id: SecureRandom.uuid)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('rejected')
  end

  it 'recovers an enqueue failure from PostgreSQL without the listener sending twice' do
    allow(JrcBroker::WebhookObligationJob).to receive(:perform_later).and_raise(Errno::ECONNREFUSED)
    expect { message.save! }.not_to raise_error
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(JrcBroker::WebhookObligationJob).to receive(:perform_later).and_call_original
    expect { JrcBroker::WebhookRecoveryJob.perform_now }.to have_enqueued_job(JrcBroker::WebhookObligationJob).with(obligation.id)
    event = Events::Base.new('message.created', Time.current, message: message)
    expect { WebhookListener.instance.message_created(event) }.not_to have_enqueued_job(WebhookJob)
  end

  it 'recovers an expired process lease and preserves the delivery ID after a lost ACK' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    obligation.update!(state: 'running', lease_token: SecureRandom.uuid, lease_until: 1.minute.ago)
    effects = Set.new
    calls = 0
    allow(SafeFetch).to receive(:fetch) do |_url, **options|
      effects << options.fetch(:headers).fetch('X-Chatwoot-Delivery')
      calls += 1
      raise Errno::ECONNRESET if calls == 1
    end
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    travel 20.minutes do
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
      JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    end
    expect(obligation.reload.state).to eq('delivered')
    expect(calls).to eq(2)
    expect(effects.to_a).to eq([obligation.delivery_id])
  end

  it 'does not capture private messages or direct Evolution campaigns' do
    message.private = true
    message.save!
    campaign = create(:message, account: account, inbox: inbox, message_type: :outgoing,
                                additional_attributes: { jrc_campaign_evolution: true })
    expect(JrcBrokerWebhookObligation.where(message_id: [message.id, campaign.id])).to be_empty
  end

  it 'marks the message failed after a terminal rejection' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('403 synthetic rejection'))
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('failed')
    expect(message.reload.status).to eq('failed')
  end

  it 'does not send again after an exhausted lease expires' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    obligation.update!(state: 'running', attempts: 8, lease_token: SecureRandom.uuid, lease_until: 1.minute.ago)
    expect(SafeFetch).not_to receive(:fetch)
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('failed')
  end

  it 'allows deletion of an account without orphaning its delivery obligations' do
    message.save!
    expect { account.destroy! }.not_to raise_error
    expect(JrcBrokerWebhookObligation.where(account_id: account.id)).to be_empty
  end

  it 'rolls back terminal settlement if updating the message fails' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('403 synthetic rejection'))
    allow(Messages::StatusUpdateService).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'synthetic DB failure')
    expect { JrcBroker::WebhookObligationJob.perform_now(obligation.id) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(obligation.reload.state).to eq('running')
    expect(message.reload.status).to eq('sent')
  end

  it 'preserves a delivered message when a late terminal attempt fails' do
    message.save!
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    message.update!(status: :delivered)
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('403 synthetic rejection'))
    JrcBroker::WebhookObligationJob.perform_now(obligation.id)
    expect(obligation.reload.state).to eq('failed')
    expect(message.reload.status).to eq('delivered')
  end
end
