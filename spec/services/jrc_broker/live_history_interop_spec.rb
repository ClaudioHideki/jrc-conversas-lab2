require 'rails_helper'

# Integration coverage spans both protocols with independent presentation fixtures.
# rubocop:disable RSpec/DescribeClass, RSpec/MultipleMemoizedHelpers
RSpec.describe 'Immutable LIVE and history custody interoperability' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:organization) { SecureRandom.uuid }
  let(:integration) { SecureRandom.uuid }
  let(:instance) { SecureRandom.uuid }
  let(:broker_message_id) { SecureRandom.uuid }
  let(:broker_conversation_id) { SecureRandom.uuid }
  let(:recipient) { { 'kind' => 'INDIVIDUAL', 'jid' => "#{SecureRandom.random_number(10**15)}@lid", 'name' => 'Synthetic interop' } }
  let(:history_scope) do
    { 'organization_id' => organization, 'integration_id' => integration, 'instance_id' => instance,
      'destination_revision' => 1, 'history_account_identity' => SecureRandom.uuid }
  end
  let(:history) { JrcBroker::HistorySyncV2.new(account: account, user: admin, access_token: admin.access_token) }
  let(:live) { JrcBroker::LiveIngress.new(account: account, user: admin, access_token: admin.access_token) }
  let(:route) do
    history.bootstrap(inbox.id, history_scope.merge('broker_contact_id' => SecureRandom.uuid, 'broker_conversation_id' => broker_conversation_id,
                                                    'recipient' => recipient, 'occurred_at' => 2.days.ago.to_i, 'conversation_id' => nil))
  end
  let(:history_input) do
    history_scope.merge('broker_conversation_id' => broker_conversation_id, 'broker_message_id' => broker_message_id,
                        'provider_message_id' => 'SYNTHETIC-INTEROP', 'content' => { 'type' => 'TEXT', 'text' => 'Synthetic interop body' },
                        'direction' => 'incoming', 'participant_jid' => recipient['kind'] == 'GROUP' ? '123@lid' : nil,
                        'occurred_at' => 1.day.ago.to_i, 'status' => 'delivered')
  end
  let(:bytes) { File.binread(Rails.root.join('spec/assets/sample.png')) }
  let(:descriptor) do
    { 'reference_id' => SecureRandom.uuid, 'media_type' => 'IMAGE', 'filename' => 'sample.png', 'mime_type' => 'image/png',
      'byte_size' => bytes.bytesize, 'sha256' => Digest::SHA256.hexdigest(bytes) }
  end

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_HISTORY_SYNC_V2_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!('jrc_broker')
    JrcBrokerIntegration.create!(account: account, organization_id: organization, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration, instance_id: instance)
    route
    clear_enqueued_jobs
  end

  # Independent reference transformation: never call the production presentation helper.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def native_input(input = history_input, origin = 'LIVE')
    raw = input.dig('content', input.dig('content', 'type') == 'MEDIA' ? 'caption' : 'text')
    text = if origin == 'EXTERNAL_OBSERVED'
             "[Saída observada no WhatsApp]#{raw.empty? && recipient['kind'] != 'GROUP' ? '' : "\n#{raw}"}"
           elsif recipient['kind'] == 'GROUP' && input['direction'] == 'incoming'
             "[Participante: #{input.fetch('participant_jid')}]\n#{raw}"
           else
             raw
           end
    envelope = history_scope.except('history_account_identity').merge(
      'protocol' => 'jrc-live-ingress/1', 'broker_message_id' => broker_message_id, 'conversation_id' => route.fetch(:conversation_id),
      'message_type' => input.fetch('direction'), 'message_origin' => origin, 'content' => text,
      'media' => input.dig('content', 'type') == 'MEDIA' ? input.fetch('content').slice('filename', 'mime_type', 'byte_size', 'sha256') : nil
    )
    canonicalizer = Object.new.extend(JrcBroker::LiveIngressContract)
    envelope.merge('request_hash' => Digest::SHA256.hexdigest(JSON.generate(canonicalizer.canonical(envelope))))
  end

  shared_examples 'custody shared across protocols' do
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    it 'reuses the exact native text message silently when history subsequently arrives' do
      receipt = live.receive(inbox.id, native_input)
      message = Message.find(receipt.fetch('message_id'))
      original = message.attributes
      clear_enqueued_jobs
      expect { history.call(inbox.id, history_input) }.not_to change(Message, :count)
      expect(JrcBrokerHistoryReceipt.find_by!(source_id: broker_message_id).message_id).to eq(message.id)
      expect(message.reload.attributes.except('status')).to eq(original.except('status'))
      expect(enqueued_jobs).to be_empty
    end

    it 'reuses newly proven historical text for LIVE without callbacks or mutation' do
      result = history.call(inbox.id, history_input)
      message = Message.find(result.fetch(:message_id))
      original = message.attributes
      clear_enqueued_jobs
      expect { live.receive(inbox.id, native_input) }.not_to change(Message, :count)
      expect(JrcBrokerLiveReceipt.find_by!(broker_message_id: broker_message_id).message_id).to eq(message.id)
      expect(message.reload.attributes).to eq(original)
      expect(enqueued_jobs).to be_empty
    end

    it 'reuses native physical media while retaining both private KEEP objects' do
      input = history_input.merge('content' => descriptor.merge('type' => 'MEDIA', 'caption' => 'Synthetic caption'))
      native = live.receive(inbox.id, native_input(input), StringIO.new(bytes))
      JrcBroker::LiveIngressMediaJob.perform_now(native.fetch('receipt_id'))
      message = JrcBrokerLiveReceipt.find(native.fetch('receipt_id')).message
      original_blob_id = message.attachments.sole.file.blob_id
      JrcBroker::HistorySyncMedia.new(history).upload(inbox.id, history_scope, descriptor, StringIO.new(bytes))
      clear_enqueued_jobs
      expect { history.call(inbox.id, input) }.not_to change(Message, :count)
      intent = JrcBrokerHistoryMedia.find_by!(reference_id: descriptor.fetch('reference_id'))
      JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
      expect(intent.reload.state).to eq('READY')
      expect(message.attachments.reload.sole.file.blob_id).to eq(original_blob_id)
      expect(intent.blob_id).not_to eq(original_blob_id)
      expect(enqueued_jobs.map { |job| job[:job] }.uniq).to eq([JrcBroker::HistorySyncMediaJob])
    end

    it 'reuses verified historical media for LIVE with no second attachment or publication' do
      input = history_input.merge('content' => descriptor.merge('type' => 'MEDIA', 'caption' => 'Synthetic caption'))
      JrcBroker::HistorySyncMedia.new(history).upload(inbox.id, history_scope, descriptor, StringIO.new(bytes))
      historical = history.call(inbox.id, input)
      intent = JrcBrokerHistoryMedia.find_by!(reference_id: descriptor.fetch('reference_id'))
      JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
      original = Message.find(historical.fetch(:message_id)).attributes
      clear_enqueued_jobs
      receipt = nil
      expect { receipt = live.receive(inbox.id, native_input(input), StringIO.new(bytes)) }.not_to change(Message, :count)
      expect(receipt).to include('state' => 'PERSISTED', 'message_id' => historical.fetch(:message_id))
      expect(Message.find(receipt.fetch('message_id')).attributes).to eq(original)
      expect(enqueued_jobs).to be_empty
    end
  end

  it_behaves_like 'custody shared across protocols'

  it 'does not upgrade a legacy historical receipt without immutable physical scope context' do
    allow(history).to receive(:receipt_origin_context).and_return(nil)
    historical = history.call(inbox.id, history_input)
    expect do
      live.receive(inbox.id, native_input)
    end.to raise_error(ArgumentError, 'JRC_INGRESS_LEGACY_UNPROVEN')
    expect(account.messages.count).to eq(1)
    expect(Message.find(historical.fetch(:message_id)).content_attributes['jrc_broker_historical']).to be(true)
    expect(JrcBrokerLiveReceipt.where(account: account)).to be_empty
  end

  it 'does not reuse a historical receipt after the physical instance epoch changes' do
    history.call(inbox.id, history_input)
    binding = JrcBrokerInboxBinding.find_by!(account: account, inbox: inbox)
    binding.update!(instance_id: SecureRandom.uuid)
    input = native_input.merge('instance_id' => binding.instance_id)
    canonicalizer = Object.new.extend(JrcBroker::LiveIngressContract)
    input['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(canonicalizer.canonical(input.except('request_hash'))))
    expect { live.receive(inbox.id, input) }.to raise_error(ArgumentError, 'JRC_INGRESS_LEGACY_UNPROVEN')
    expect(account.messages.count).to eq(1)
  end

  it 'does not duplicate a native pending media reservation when history arrives first at completion' do
    input = history_input.merge('content' => descriptor.merge('type' => 'MEDIA', 'caption' => 'Synthetic caption'))
    pending = live.receive(inbox.id, native_input(input), StringIO.new(bytes))
    JrcBroker::HistorySyncMedia.new(history).upload(inbox.id, history_scope, descriptor, StringIO.new(bytes))
    expect { history.call(inbox.id, input) }.to raise_error(ArgumentError, 'JRC_INGRESS_PENDING')
    expect(account.messages.count).to eq(0)
    JrcBroker::LiveIngressMediaJob.perform_now(pending.fetch('receipt_id'))
    expect { history.call(inbox.id, input) }.not_to change(Message, :count)
  end

  it 'refuses mutable content changes despite a valid original native receipt and matching UUID' do
    receipt = live.receive(inbox.id, native_input)
    Message.find(receipt.fetch('message_id')).update!(content: 'Edited synthetic body')
    expect { history.call(inbox.id, history_input) }.to raise_error(ArgumentError, 'JRC_INGRESS_MESSAGE')
    expect(JrcBrokerHistoryReceipt.where(account: account, record_kind: 'MESSAGE')).to be_empty
  end

  it 'keeps new historical origin context immutable under direct SQL' do
    history.call(inbox.id, history_input)
    receipt = JrcBrokerHistoryReceipt.find_by!(account: account, source_id: broker_message_id)
    expect do
      JrcBrokerHistoryReceipt.transaction(requires_new: true) do
        JrcBrokerHistoryReceipt.where(id: receipt.id).update_all(origin_context: nil) # rubocop:disable Rails/SkipsModelValidations
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /JRC_HISTORY_ORIGIN_IMMUTABLE/)
  end

  it 'advances native status monotonically from a matching silent historical fact' do
    receipt = live.receive(inbox.id, native_input)
    message = Message.find(receipt.fetch('message_id'))
    history.call(inbox.id, history_input.merge('status' => 'read'))
    expect(message.reload).to be_read
    history.call(inbox.id, history_input.merge('status' => 'sent'))
    expect(message.reload).to be_read
  end

  it 'refuses a different offered source clock when native custody already exists' do
    input = native_input.merge('occurred_at' => history_input.fetch('occurred_at') - 1)
    canonicalizer = Object.new.extend(JrcBroker::LiveIngressContract)
    input['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(canonicalizer.canonical(input.except('request_hash'))))
    live.receive(inbox.id, input)
    expect { history.call(inbox.id, history_input) }.to raise_error(ArgumentError, 'JRC_INGRESS_CLOCK')
    expect(account.messages.count).to eq(1)
  end

  it 'refuses an offered LIVE clock that differs from immutable historical custody' do
    history.call(inbox.id, history_input)
    input = native_input.merge('occurred_at' => history_input.fetch('occurred_at') + 1)
    canonicalizer = Object.new.extend(JrcBroker::LiveIngressContract)
    input['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(canonicalizer.canonical(input.except('request_hash'))))
    expect { live.receive(inbox.id, input) }.to raise_error(ArgumentError, 'JRC_INGRESS_CLOCK')
    expect(account.messages.count).to eq(1)
  end

  it 'does not turn a silently adopted historical fact into a newly unread LIVE event' do
    conversation = account.conversations.find_by!(display_id: route.fetch(:conversation_id))
    conversation.update!(agent_last_seen_at: Time.current)
    history.call(inbox.id, history_input)
    expect(conversation.reload.unread_incoming_messages).to be_empty
    live.receive(inbox.id, native_input)
    expect(conversation.reload.unread_incoming_messages).to be_empty
    expect(JrcBrokerLiveReceipt.find_by!(account: account, broker_message_id: broker_message_id).published_at).to be_nil
  end

  context 'with an explicit group and LID participant' do
    let(:recipient) do
      { 'kind' => 'GROUP', 'jid' => "#{SecureRandom.random_number(10**18)}@g.us", 'name' => 'Synthetic group', 'group_scope' => 'a' * 64 }
    end

    it_behaves_like 'custody shared across protocols'

    %w[LIVE EXTERNAL_OBSERVED].each do |origin|
      it "reuses historical outgoing empty-caption media with exact #{origin} group presentation" do
        input = history_input.merge('direction' => 'outgoing', 'participant_jid' => nil,
                                    'content' => descriptor.merge('type' => 'MEDIA', 'caption' => ''))
        JrcBroker::HistorySyncMedia.new(history).upload(inbox.id, history_scope, descriptor, StringIO.new(bytes))
        historical = history.call(inbox.id, input)
        JrcBroker::HistorySyncMediaJob.perform_now(JrcBrokerHistoryMedia.find_by!(reference_id: descriptor.fetch('reference_id')).id)
        request = native_input(input, origin)
        request['content'] = origin == 'LIVE' ? '[Anexo]' : "[Saída observada no WhatsApp]\n[Anexo]"
        canonicalizer = Object.new.extend(JrcBroker::LiveIngressContract)
        request['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(canonicalizer.canonical(request.except('request_hash'))))
        clear_enqueued_jobs
        expect(live.receive(inbox.id, request, StringIO.new(bytes))).to include('state' => 'PERSISTED', 'message_id' => historical.fetch(:message_id))
        expect(enqueued_jobs).to be_empty
      end
    end

    it 'refuses a different participant rather than stripping the group prefix' do
      live.receive(inbox.id, native_input)
      expect { history.call(inbox.id, history_input.merge('participant_jid' => '456@lid')) }.to raise_error(ArgumentError, 'JRC_INGRESS_CONTENT')
      expect(account.messages.count).to eq(1)
    end
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleMemoizedHelpers
