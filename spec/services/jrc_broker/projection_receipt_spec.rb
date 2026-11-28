require 'rails_helper'

RSpec.describe JrcBroker::ProjectionReceipt do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:integration) do
    JrcBrokerIntegration.create!(account: account, organization_id: SecureRandom.uuid, destination_revision: 1,
                                 broker_origin: 'https://broker.example.test', encrypted_control_key: 'fixture')
  end
  let!(:binding) { JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:canonical) { SecureRandom.uuid }
  let(:channel) { SecureRandom.uuid }
  let(:broker_conversation) { SecureRandom.uuid }
  let(:peer) { '15551234567@s.whatsapp.net' }
  let(:marker) { {'jrc_broker_message_id' => canonical} }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content_attributes: marker) }
  let(:obligation) { JrcBrokerWebhookObligation.find_by!(message_id: message.id) }
  let(:scope) { {'organization_id' => integration.organization_id, 'channel_id' => channel} }
  let(:proof) do
    source = conversation.contact_inbox.source_id
    base = scope.merge('kind' => 'BROKER_MIRROR_RECEIPT_V1', 'account_id' => account.id, 'inbox_id' => inbox.id,
                       'integration_id' => binding.integration_id, 'instance_id' => binding.instance_id, 'destination_revision' => 1,
                       'remote_conversation_id' => conversation.display_id, 'message_id' => message.id, 'rails_conversation_id' => conversation.id,
                       'delivery_id' => obligation.delivery_id, 'expected_updated_at' => message.updated_at.utc.iso8601(6),
                       'peer' => peer, 'contact_inbox_id' => conversation.contact_inbox_id, 'contact_id' => conversation.contact_id,
                       'route_source_sha256' => Digest::SHA256.hexdigest(source), 'media_error' => 'MEDIA_NOT_FOUND')
    base.merge('mapping' => base.slice('organization_id','integration_id','channel_id','remote_conversation_id','message_id').merge(
      'canonical_message_id' => canonical, 'broker_conversation_id' => broker_conversation, 'peer' => peer
    ), 'canonical' => scope.merge('id' => canonical, 'direction' => 'OUTGOING', 'source' => 'OPERATOR', 'conversation_id' => broker_conversation,
                                  'provider_message_id' => 'fixture-key', 'state' => 'READ'),
               'provider' => scope.merge('state' => 'READ', 'peer' => peer, 'from_me' => true, 'provider_message_id' => 'fixture-key',
                                         'instance_id' => binding.instance_id, 'record_sha256' => 'c' * 64))
  end
  let(:digest) { 'a' * 64 }

  before do
    conversation.contact.update!(phone_number: '+15551234567')
    obligation.update!(state: 'delivered')
    message.attachments.create!(account: account, file_type: :image)
    message.update_columns(status: 'failed', content_attributes: message.content_attributes.merge('external_error' => 'MEDIA_NOT_FOUND'))
  end

  it 'adds the validated transport audit with no callback and leaves media state untouched on reapplication' do
    before_count = JrcBrokerWebhookObligation.count
    before_status = message.status
    expect(described_class.new(proof, digest).perform).to eq(:eligible)
    expect { @result = described_class.new(proof, digest).perform(apply: true) }.not_to have_enqueued_job
    expect(@result).to eq(:recorded)
    expect(message.reload.status).to eq(before_status)
    expect(message.external_error).to eq('MEDIA_NOT_FOUND')
    expect(message.attachments.count).to eq(1)
    expect(message.display_content_attributes['jrc_delivery_projection']).to eq({'state' => 'READ', 'kind' => 'BROKER_MIRROR_RECEIPT_V1'})
    expect(JrcBrokerWebhookObligation.count).to eq(before_count)
    expect { expect(described_class.new(proof, digest).perform(apply: true)).to eq(:already_confirmed) }.not_to change(Audited::Audit, :count)
  end

  it 'discards a client-supplied display assertion without a matching audit record' do
    message.update_columns(content_attributes: message.content_attributes.merge('jrc_delivery_projection' => {'state' => 'READ'}))
    expect(message.reload.display_content_attributes).not_to include('jrc_delivery_projection')
  end

  it 'keeps a late generic status and an authenticated channel ACK from clearing the recorded media issue' do
    expect(Messages::StatusUpdateService.new(message, 'delivered').perform).to be(false)
    receipt = {'version' => 1, 'canonical_message_id' => canonical, 'provider_message_id' => 'fixture-key', 'state' => 'READ'}
    expect { JrcBroker::OutboundReceipt.new(message, status: 'read', proof: receipt).perform }.not_to have_enqueued_job
    expect(message.reload).to be_failed
    expect(message.external_error).to eq('MEDIA_NOT_FOUND')
    expect(message.content_attributes.dig('jrc_broker_outbound','state')).to eq('READ')
  end

  it 'refuses a stale baseline, an unrelated peer, a different canonical and an incoming provider key' do
    [proof.merge('expected_updated_at' => 'stale'), proof.merge('peer' => '15550000000@s.whatsapp.net'),
     proof.merge('canonical' => proof['canonical'].merge('id' => SecureRandom.uuid)),
     proof.merge('provider' => proof['provider'].merge('from_me' => false))].each do |invalid|
      expect { described_class.new(invalid, digest).perform(apply: true) }.to raise_error(ArgumentError, /JRC_RECEIPT/)
    end
    expect(message.reload.content_attributes).not_to include(described_class::POINTER)
  end

  context 'when the provider delivered a native human TEXT on its own transport' do
    let(:marker) { {} }
    let(:direct_proof) do
      receipt = {'protocol' => 'DIRECT_EVOLUTION_RECEIPT_V1', 'organizationId' => integration.organization_id,
                 'integrationId' => binding.integration_id, 'channelId' => channel, 'jobId' => SecureRandom.uuid,
                 'origin' => ENV.fetch('FRONTEND_URL').delete_suffix('/'), 'accountId' => account.id, 'inboxId' => inbox.id,
                 'conversationId' => conversation.display_id, 'messageId' => message.id, 'destinationRevision' => 1, 'credentialRevision' => 1,
                 'obligationId' => obligation.delivery_id, 'intentId' => obligation.delivery_id,
                 'instanceId' => 'direct-legacy-instance', 'generation' => 'first', 'peer' => peer,
                 'sourceId' => 'WAID:fixture', 'providerMessageId' => 'fixture', 'state' => 'READ', 'evidenceSha256' => 'b' * 64}
      job = receipt.slice('organizationId','integrationId').merge('id' => receipt['jobId'], 'status' => 'SUCCEEDED', 'kind' => 'CHATWOOT_REPLY',
        'payload' => {'directEvolutionReceipt' => receipt})
      proof.except('mapping','provider','canonical','media_error').merge('kind' => receipt['protocol'], 'job' => job)
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('FRONTEND_URL').and_return('https://fixture.example.test')
      message.attachments.destroy_all
      message.update_columns(status: 'sent', sender_type: 'User', sender_id: create(:user, account: account).id,
                             source_id: 'WAID:fixture', content_attributes: message.content_attributes.except('external_error'))
    end

    it 'records the direct receipt only after job closure and requires the original WAID' do
      wrong_job = direct_proof['job'].merge('status' => 'PENDING')
      expect { described_class.new(direct_proof.merge('job' => wrong_job), digest).perform(apply: true) }.to raise_error(ArgumentError, /JRC_RECEIPT_JOB/)
      message.update_columns(source_id: 'WAID:other')
      expect { described_class.new(direct_proof, digest).perform(apply: true) }.to raise_error(ArgumentError, /JRC_RECEIPT_DIRECT_IDENTITY/)
      message.update_columns(source_id: 'WAID:fixture')
      expect { described_class.new(direct_proof, digest).perform(apply: true) }.not_to have_enqueued_job
      expect(message.reload.display_content_attributes[described_class::DISPLAY]).to eq({'kind' => 'DIRECT_EVOLUTION_RECEIPT_V1','state' => 'READ'})
      expect(message.content_attributes.dig('jrc_broker_outbound','canonical_message_id')).to be_nil
      expect(message.status).to eq('sent')
    end
  end
end
