require 'rails_helper'

RSpec.describe JrcBroker::OutboundReceipt do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:binding) do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end
  let(:message) { create(:message, account: account, inbox: inbox, message_type: :outgoing) }
  let(:proof) { { 'version' => 1, 'canonical_message_id' => SecureRandom.uuid, 'provider_message_id' => 'synthetic-provider-id', 'state' => 'SENT' } }

  it 'persists provider confirmation together with the native status and preserves unrelated attributes' do
    message.update!(content_attributes: message.content_attributes.merge('retained' => 'synthetic'))
    described_class.new(message, status: 'sent', proof: proof).perform
    expect(message.reload.content_attributes['retained']).to eq('synthetic')
    expect(message.content_attributes['jrc_broker_outbound']).to include(proof)
    expect(message.content_attributes.dig('jrc_broker_outbound',
                                          'intent_id')).to eq(JrcBrokerWebhookObligation.find_by!(message_id: message.id).delivery_id)
    expect(message.status).to eq('sent')
  end

  it 'does not emit another message_created webhook obligation when confirming status' do
    message
    expect { described_class.new(message, status: 'sent', proof: proof).perform }.not_to change(JrcBrokerWebhookObligation, :count)
  end

  it 'requires a provider ID before confirming a successful send' do
    expect { described_class.new(message, status: 'sent', proof: proof.merge('provider_message_id' => nil)).perform }
      .to raise_error(ArgumentError, 'invalid_broker_delivery_receipt')
    expect(message.reload.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('PENDING')
  end

  it 'accepts the same 512 character provider ID boundary as the Broker' do
    described_class.new(message, status: 'sent', proof: proof.merge('provider_message_id' => 'p' * 512)).perform
    expect(message.reload.content_attributes.dig('jrc_broker_outbound', 'provider_message_id')).to eq('p' * 512)
  end

  ['p' * 513, 'provider id', "provider\nvalue", "provider\u00a0value"].each do |provider|
    it "rejects a provider ID outside the shared contract: #{provider.length} characters #{provider.inspect[0, 24]}" do
      expect { described_class.new(message, status: 'sent', proof: proof.merge('provider_message_id' => provider)).perform }
        .to raise_error(ArgumentError, 'invalid_broker_delivery_receipt')
    end
  end

  it 'accepts an authoritative failure before a provider ID exists' do
    failed = proof.merge('state' => 'FAILED', 'provider_message_id' => nil)
    described_class.new(message, status: 'failed', proof: failed, external_error: 'SYNTHETIC_REJECTION').perform
    expect(message.reload).to be_failed
    expect(message.external_error).to eq('SYNTHETIC_REJECTION')
    expect(message.content_attributes['jrc_broker_outbound']).to include(failed)
  end

  it 'does not regress a read receipt when sent arrives late through a stale model instance' do
    stale = Message.find(message.id)
    described_class.new(message, status: 'read', proof: proof.merge('state' => 'READ')).perform
    described_class.new(stale, status: 'sent', proof: proof).perform
    expect(message.reload).to be_read
    expect(message.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('READ')
  end

  %w[sent failed].each do |late_status|
    it "serializes a stale legacy #{late_status} update loaded before the first receipt marker existed" do
      message.update!(content_attributes: {})
      stale = Message.find(message.id)
      described_class.new(message, status: 'read', proof: proof.merge('state' => 'READ')).perform
      Messages::StatusUpdateService.new(stale, late_status, 'SYNTHETIC_LATE_CALLBACK').perform
      expect(message.reload).to be_read
      expect(message.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('READ')
      expect(message.external_error).to be_nil
    end
  end

  it 'rejects replacing a confirmed canonical identity' do
    described_class.new(message, status: 'sent', proof: proof).perform
    expect do
      described_class.new(message, status: 'delivered',
                                   proof: proof.merge('state' => 'DELIVERED', 'canonical_message_id' => SecureRandom.uuid)).perform
    end
      .to raise_error(ArgumentError, 'broker_delivery_identity_changed')
    expect(message.reload).to be_sent
  end

  it 'records a provider rejection after sent without claiming delivery' do
    described_class.new(message, status: 'sent', proof: proof).perform
    described_class.new(message, status: 'failed', proof: proof.merge('state' => 'FAILED'), external_error: 'SYNTHETIC_FAILURE').perform
    expect(message.reload).to be_failed
    expect(message.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('FAILED')
  end

  it 'rejects confirmation for a replaced inbox binding' do
    message
    binding.update!(instance_id: SecureRandom.uuid)
    expect { described_class.new(message, status: 'sent', proof: proof).perform }
      .to raise_error(ArgumentError, 'broker_delivery_context_changed')
    expect(message.reload.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('PENDING')
  end

  it 'rejects a mismatched native status and unknown receipt keys' do
    expect { described_class.new(message, status: 'delivered', proof: proof).perform }
      .to raise_error(ArgumentError, 'invalid_broker_delivery_receipt')
    expect { described_class.new(message, status: 'sent', proof: proof.merge('unexpected' => true)).perform }
      .to raise_error(ArgumentError, 'invalid_broker_delivery_receipt')
  end

  it 'rejects receipt proof on an unbound API inbox' do
    binding.destroy!
    expect { described_class.new(message, status: 'sent', proof: proof).perform }
      .to raise_error(ArgumentError, 'broker_delivery_context_changed')
  end
end
