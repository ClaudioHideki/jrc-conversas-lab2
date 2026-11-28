require 'rails_helper'

RSpec.describe JrcBroker::UnboundProviderReceipt do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_api, account: account, webhook_url: 'https://evolution.example.test/chatwoot/webhook/fixture') }
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: user, content: 'test body', source_id: 'WAID:fixture') }
  let(:origin) { 'https://group.example.test' }
  let(:peer) { '15550000001@s.whatsapp.net' }
  let(:digest) { 'a' * 64 }
  let(:input) do
    ids = {'account_id' => account.id, 'inbox_id' => inbox.id, 'message_id' => message.id}
    grant = ids.except('message_id').merge('origin' => origin, 'kind' => 'EXCLUSIVE_DIRECT_EVOLUTION', 'webhook_url_sha256' => Digest::SHA256.hexdigest(channel.webhook_url),
      'snapshot_sha256' => digest, 'physical_instance_id' => 'legacy', 'generation' => 'generation-1',
      'valid_from' => (message.created_at-1.minute).utc.iso8601, 'valid_until' => (message.created_at+1.minute).utc.iso8601)
    scan = ids.merge('origin' => origin,'tenant_count' => 1,'connections' => 0,'jobs' => 0,'linked_messages' => 0)
    provider = ids.merge('origin' => origin,'row_id' => 'm','ack_id' => 'u','instance_id' => 'legacy','peer' => peer,'remote_jid' => peer,
      'key_id' => 'fixture','from_me' => true,'ack' => 'READ','conversation_id' => conversation.display_id,'part_count' => 1,
      'body_sha256' => Digest::SHA256.hexdigest(message.content), 'record_sha256' => digest, 'message_timestamp' => message.created_at.to_i)
    ids.merge('kind' => described_class::KIND, 'rails_conversation_id' => conversation.id, 'remote_conversation_id' => conversation.display_id,
      'contact_id' => conversation.contact_id,'contact_inbox_id' => conversation.contact_inbox_id,
      'route_source_sha256' => Digest::SHA256.hexdigest(conversation.contact_inbox.source_id), 'peer' => peer,
      'expected_updated_at' => message.updated_at.utc.iso8601(6),'broker_scan' => scan,'custody' => grant,'provider' => provider)
  end
  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('FRONTEND_URL').and_return(origin)
    conversation.contact.update!(phone_number: '+15550000001')
    message.update_columns(status: 'failed',content_attributes: {'external_error'=>'fixture-diagnostic'})
  end

  it 'records only the audit pointer, retaining the original status and diagnostic across a repeated application' do
    project = JrcBroker::ProjectionReceipt.new(input,digest)
    expect(project.perform).to eq(:eligible)
    expect { expect(project.perform(apply: true)).to eq(:recorded) }.not_to have_enqueued_job
    expect(project.perform(apply: true)).to eq(:already_confirmed)
    expect(message.reload.display_content_attributes[JrcBroker::ProjectionReceipt::DISPLAY]).to eq({'kind'=>described_class::KIND,'state'=>'READ'})
    expect(message.status).to eq('failed')
    expect(message.external_error).to eq('fixture-diagnostic')
    expect(JrcBrokerWebhookObligation.exists?(message_id: message.id)).to be(false)
  end

  it 'blocks transport ambiguity, unrelated source/peer, weak acknowledgments and changed webhook' do
    [[%w[broker_scan jobs],1],[%w[broker_scan connections],1],[%w[provider peer],'other'],[%w[provider key_id],'another'],
     [%w[provider ack],'SERVER_ACK'],[%w[provider part_count],2],[%w[custody webhook_url_sha256],'b'*64]].each do |(section,key),bad|
      copy=input.deep_dup
      copy.fetch(section)[key]=bad
      expect { JrcBroker::ProjectionReceipt.new(copy,digest).perform(apply: true) }.to raise_error(ArgumentError,/JRC_DIRECT_RECEIPT_NOT_PROVEN/)
    end
    expect(message.reload.content_attributes).not_to have_key(JrcBroker::ProjectionReceipt::POINTER)
  end

  it 'accepts an exact delivered receipt on a previously cursor-promoted original only in its configured route' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return(origin)
    neighbor = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                                sender: user, content: message.content, source_id: 'WAID:neighbor', status: :read)
    message.update_columns(status: :read)
    proof = input.deep_dup
    proof['provider']['ack'] = 'DELIVERY_ACK'
    project = JrcBroker::ProjectionReceipt.new(proof, digest)
    expect { project.perform }.to raise_error(ArgumentError, /JRC_DIRECT_RECEIPT_NOT_PROVEN/)
    channel.update!(additional_attributes: {Messages::DirectWaidRetryGuard::SETTING => {
      'version' => 1, 'origin' => origin, 'account_id' => account.id, 'inbox_id' => inbox.id,
      'webhook_url_sha256' => Digest::SHA256.hexdigest(channel.webhook_url)
    }})
    expect { expect(project.perform(apply: true)).to eq(:recorded) }.not_to have_enqueued_job
    expect(message.reload.display_content_attributes[JrcBroker::ProjectionReceipt::DISPLAY]['state']).to eq('DELIVERED')
    expect(neighbor.reload.display_content_attributes).to include('jrc_direct_individual_receipt_required' => true)
    expect(neighbor.display_content_attributes).not_to include(JrcBroker::ProjectionReceipt::DISPLAY)
  end

  it 'rejects a source ID shared by two local originals on the route' do
    create(:message, account: account, inbox: inbox, conversation: conversation, source_id: message.source_id)
    expect { JrcBroker::ProjectionReceipt.new(input, digest).perform }.to raise_error(ArgumentError, /JRC_DIRECT_RECEIPT_NOT_PROVEN/)
  end
end
