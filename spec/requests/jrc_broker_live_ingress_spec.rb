require 'rails_helper'

RSpec.describe 'Native Broker LIVE custody', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  # Cross-layer atomic custody checks deliberately assert identity, effects and bytes together.
  # rubocop:disable RSpec/MultipleExpectations
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:integration) do
    JrcBrokerIntegration.create!(account: account, organization_id: SecureRandom.uuid, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
  end
  let(:binding) { JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid) }
  let(:scope) do
    { 'protocol' => 'jrc-live-ingress/1', 'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id,
      'instance_id' => binding.instance_id, 'destination_revision' => 1 }
  end
  let(:envelope) do
    seal(scope.merge('broker_message_id' => SecureRandom.uuid, 'conversation_id' => conversation.display_id,
                     'message_type' => 'incoming', 'message_origin' => 'LIVE', 'content' => 'Synthetic LIVE', 'media' => nil))
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_broker/inboxes/#{inbox.id}/live-ingress/v1" }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('jrc_broker')
    scope
    headers
    conversation
    clear_enqueued_jobs
  end

  def seal(value)
    value = value.except('request_hash')
    value.merge('request_hash' => Digest::SHA256.hexdigest(JSON.generate(canonical(value))))
  end

  def canonical(value)
    return value.keys.sort.index_with { |key| canonical(value[key]) } if value.is_a?(Hash)
    return value.map { |entry| canonical(entry) } if value.is_a?(Array)

    value
  end

  def send_text(input = envelope)
    post "#{base}/messages", params: input, headers: headers, as: :json
  end

  def lookup(input = envelope)
    post "#{base}/receipts/#{input.fetch('broker_message_id')}", params: scope.merge('request_hash' => input.fetch('request_hash')),
                                                                 headers: headers, as: :json
  end

  it 'advertises only the current exact administrator token scope' do
    post "#{base}/capability", params: scope, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(scope.merge('account_id' => account.id, 'inbox_id' => inbox.id,
                                                        'supports_text' => true, 'supports_media' => true, 'max_media_bytes' => 16.megabytes))
  end

  it 'admits the exact UTF-8 content byte bound even when JSON escaping expands its wire size' do
    send_text(seal(envelope.merge('content' => "\n" * 65_536)))
    expect(response).to have_http_status(:ok)
    send_text(seal(envelope.merge('content' => 'a' * 65_537)))
    expect(response).to have_http_status(:conflict)
  end

  it 'orders a delayed LIVE source event before a recent message without regressing conversation or websocket activity' do
    recent = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    clock = 1.day.ago.to_i
    send_text(seal(envelope.merge('occurred_at' => clock)))
    expect(response).to have_http_status(:ok)
    older = Message.find(response.parsed_body.fetch('message_id'))
    expect(older.created_at.to_i).to eq(clock)
    expect(conversation.reload.last_activity_at.to_i).to eq(recent.created_at.to_i)
    expect(older.push_event_data.dig(:conversation, :last_activity_at)).to eq(conversation.last_activity_at.to_i)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: headers, as: :json
    expect(response.parsed_body.fetch('payload').map { |row| row.fetch('id') }).to eq([older.id, recent.id])
  end

  it 'replaces only an empty conversation arrival anchor with its first proven LIVE source clock' do
    clock = 2.days.ago.to_i
    send_text(seal(envelope.merge('occurred_at' => clock)))
    expect(response).to have_http_status(:ok)
    message = Message.find(response.parsed_body.fetch('message_id'))
    expect(message.created_at.to_i).to eq(clock)
    expect(conversation.reload.last_activity_at.to_i).to eq(clock)
  end

  it 'keeps a delayed newly admitted LIVE message unread when the agent saw the inbox before admission' do
    conversation.update!(agent_last_seen_at: 1.minute.ago, assignee_last_seen_at: 1.minute.ago)
    send_text(seal(envelope.merge('occurred_at' => 1.day.ago.to_i)))
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.unread_incoming_messages.size).to eq(1)
    expect(conversation.assignee_unread_messages.incoming.count).to eq(1)
  end

  it 'projects immutable publication time in REST and websocket reads without altering the source clock or webhook' do
    source_clock = 1.day.ago.to_i
    send_text(seal(envelope.merge('occurred_at' => source_clock)))
    receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
    message = receipt.message
    message.update!(content_attributes: message.content_attributes.merge('broker_published_at' => 1))
    original_attributes = message.reload.content_attributes.deep_dup
    expect(message.push_event_data[:broker_published_at]).to eq(receipt.published_at.to_i)
    expect(message.push_event_data[:created_at]).to eq(source_clock)
    expect(message.webhook_push_event_data).not_to have_key(:broker_published_at)
    expect(message.webhook_data).not_to have_key(:broker_published_at)
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages", headers: headers, as: :json
    row = response.parsed_body.fetch('payload').find { |entry| entry.fetch('id') == message.id }
    expect(row.fetch('broker_published_at')).to eq(receipt.published_at.to_i)
    expect(row.fetch('created_at')).to eq(source_clock)
    expect(message.reload.content_attributes).to eq(original_attributes)
  end

  it 'computes paginated unread aggregates in one query with the same publication clock' do
    conversation.update!(agent_last_seen_at: 1.minute.ago)
    send_text(seal(envelope.merge('occurred_at' => 1.day.ago.to_i)))
    other = create(:conversation, account: account, inbox: inbox, agent_last_seen_at: 1.minute.ago)
    send_text(seal(envelope.merge('broker_message_id' => SecureRandom.uuid, 'conversation_id' => other.display_id,
                                  'occurred_at' => 1.day.ago.to_i)))
    queries = []
    rows = nil
    ActiveSupport::Notifications.subscribed(lambda { |_name, _start, _finish, _id, payload|
      queries << payload[:sql] if payload[:sql].include?('jrc_broker_live_receipts')
    }, 'sql.active_record') do
      rows = account.conversations.where(id: [conversation.id, other.id])
                    .select(Conversation.arel_table[Arel.star], Conversation.unread_messages_count_arel.as('publication_unread')).to_a
    end
    expect(rows.map { |row| row['publication_unread'].to_i }).to eq([1, 1])
    expect(queries.size).to eq(1)
  end

  it 'does not accept a caller publication timestamp as server custody proof' do
    send_text(seal(envelope.merge('published_at' => Time.current.iso8601)))
    expect(response).to have_http_status(:conflict)
    expect(JrcBrokerLiveReceipt.where(account: account)).to be_empty
  end

  context 'with cached unread badges' do
    let(:unread_store) { Conversations::UnreadCounts::Store }

    before { account.enable_features!('conversation_unread_counts', 'unread_count_for_filters') }
    after { unread_store.clear_account!(account.id) }

    def delayed_incoming
      conversation.update!(agent_last_seen_at: 1.minute.ago)
      send_text(seal(envelope.merge('occurred_at' => 1.day.ago.to_i)))
      expect(response).to have_http_status(:ok)
    end

    it 'rebuilds base and assignment memberships from server publication rather than source time' do
      delayed_incoming
      Conversations::UnreadCounts::Builder.new(account).build_all!
      keys = [unread_store.inbox_key(account.id, inbox.id), unread_store.inbox_unassigned_key(account.id, inbox.id)]
      expect(unread_store.counts_for_keys(keys).values).to eq([1, 1])
    end

    it 'refreshes an already ready Redis badge when the delayed message is admitted' do
      unread_store.mark_base_ready!(account.id)
      unread_store.mark_assignment_ready!(account.id)
      delayed_incoming
      Conversations::UnreadCounts::Refresher.new(conversation.reload).perform
      key = unread_store.inbox_key(account.id, inbox.id)
      expect(unread_store.counts_for_keys([key]).fetch(key)).to eq(1)
    end

    it 'counts the delayed event through the actual saved-filter SQL service' do
      delayed_incoming
      query = { payload: [{ attribute_key: 'status', attribute_model: 'standard', filter_operator: 'equal_to', values: ['open'] }] }
      count = Conversations::UnreadCounts::FilterQueryCounter.new(account: account, user: admin, query: query).perform
      expect(count).to eq(1)
    end

    it 'counts participating unread through the filtered cache service' do
      delayed_incoming
      create(:conversation_participant, account: account, conversation: conversation, user: admin)
      counts = Conversations::UnreadCounts::FilteredCounter.new(account: account, user: admin).perform
      expect(counts[:participating_count]).to eq(1)
    end

    it 'returns the delayed event in the actual sidebar counts endpoint' do
      delayed_incoming
      get "/api/v1/accounts/#{account.id}/conversations/unread_counts", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'all_count')).to eq(1)
      expect(response.parsed_body.dig('payload', 'inboxes', inbox.id.to_s)).to eq(1)
    end

    it 'marks only the last published incoming event unread when source clocks arrived out of order' do
      now = Time.current.change(usec: 0)
      travel_to(now - 10.seconds) { send_text(seal(envelope.merge('occurred_at' => 2.days.ago.to_i))) }
      travel_to(now) { send_text(seal(envelope.merge('broker_message_id' => SecureRandom.uuid, 'occurred_at' => 3.days.ago.to_i))) }
      conversation.update!(agent_last_seen_at: now + 1.second, assignee_last_seen_at: now + 1.second)
      expect(conversation.reload.unread_incoming_messages).to be_empty
      post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/unread", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(conversation.reload.unread_incoming_messages.size).to eq(1)
      expect(conversation.agent_last_seen_at).to be_within(1.second).of(now - 1.second)
    end
  end

  it 'keeps timestamp optional and rejects malformed, unsafe or excessive future source clocks' do
    [nil, -1, 1.5, '0', Time.current.to_i + 600, 9_007_199_254_740_992].each do |clock|
      expect { send_text(seal(envelope.merge('occurred_at' => clock))) }.not_to change(Message, :count)
      expect(response).to have_http_status(:conflict)
    end
    send_text(seal(envelope.merge('occurred_at' => 0)))
    expect(response).to have_http_status(:ok)
    expect(Message.find(response.parsed_body.fetch('message_id')).created_at.to_i).to eq(0)
  end

  it 'commits one normal LIVE message and immutable receipt; lost ACK lookup and duplicate never resend' do
    input = envelope
    expect { send_text(input) }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok)
    original = response.parsed_body
    message = Message.find(original.fetch('message_id'))
    expect(original).to include(scope.merge('state' => 'PERSISTED', 'conversation_id' => conversation.display_id,
                                            'broker_message_id' => input.fetch('broker_message_id'), 'request_hash' => input.fetch('request_hash')))
    expect(message).to have_attributes(content: input.fetch('content'), sender: conversation.contact, private: false)
    expect(message.content_attributes).not_to have_key('jrc_broker_historical')
    expect(enqueued_jobs.map { |job| job[:job] }).to include(ActionCableBroadcastJob)
    clear_enqueued_jobs
    expect { send_text(input) }.not_to change(Message, :count)
    expect(response.parsed_body).to eq(original)
    expect(enqueued_jobs).to be_empty
    message.update!(content_attributes: { 'jrc_broker_message_id' => SecureRandom.uuid })
    lookup(input)
    expect(response.parsed_body).to eq(original)
  end

  it 'does not impersonate a human or stop NICO for LIVE outgoing, retaining normal callbacks' do
    input = seal(envelope.merge('message_type' => 'outgoing'))
    expect(JrcNico::DelegationService).not_to receive(:stop)
    send_text(input)
    expect(response).to have_http_status(:ok)
    expect(Message.find(response.parsed_body.fetch('message_id')).sender).to be_nil
  end

  it 'uses external echo for observed outgoing without accepting caller attributes' do
    send_text(seal(envelope.merge('message_type' => 'outgoing', 'message_origin' => 'EXTERNAL_OBSERVED')))
    expect(response).to have_http_status(:ok)
    expect(Message.find(response.parsed_body.fetch('message_id')).content_attributes['external_echo']).to be(true)
  end

  %w[content conversation_id media destination_revision].each do |key|
    it "conflicts when the existing receive key changes #{key}" do
      input = envelope
      send_text(input)
      changed = { 'content' => 'Other synthetic', 'conversation_id' => conversation.display_id + 1,
                  'media' => { 'filename' => 'x.pdf', 'mime_type' => 'application/pdf', 'byte_size' => 1, 'sha256' => 'a' * 64 },
                  'destination_revision' => 2 }
      expect { send_text(seal(input.merge(key => changed.fetch(key)))) }.not_to change(Message, :count)
      expect(response).to have_http_status(:conflict)
    end
  end

  it 'rolls back receipt and message together if receipt persistence fails' do
    allow(JrcBrokerLiveReceipt).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
    expect { send_text }.not_to change(Message, :count)
    expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(0)
    expect(response).to have_http_status(:conflict)
  end

  it 'never adopts an older editable marker as a receipt' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content_attributes: { 'jrc_broker_message_id' => envelope.fetch('broker_message_id') })
    lookup
    expect(response).to have_http_status(:not_found)
    expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(0)
  end

  it 'refuses a legacy generic public message with the same Broker UUID rather than adopting or duplicating it' do
    input = envelope
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: input.fetch('content'), content_attributes: { 'jrc_broker_message_id' => input.fetch('broker_message_id') })
    clear_enqueued_jobs
    expect { send_text(input) }.not_to change(Message, :count)
    expect(response).to have_http_status(:conflict)
    expect(JrcBrokerLiveReceipt.where(account: account)).to be_empty
    expect(enqueued_jobs).to be_empty
  end

  it 'rejects hash mismatch and unknown or nested injection keys' do
    [envelope.merge('content' => 'Tampered'), seal(envelope.merge('private' => true)),
     seal(envelope.merge('message_origin' => 'EXTERNAL_OBSERVED'))].each do |input|
      expect { send_text(input) }.not_to change(Message, :count)
      expect(response).to have_http_status(:conflict)
    end
  end

  it 'denies ordinary agents and revoked administrators without a capability downgrade' do
    agent = create(:user, account: account, role: :agent)
    post "#{base}/capability", params: scope, headers: { api_access_token: agent.access_token.token }, as: :json
    expect(response).to have_http_status(:forbidden)
    admin.account_users.find_by!(account: account).update!(role: :agent)
    send_text
    expect(response).to have_http_status(:forbidden)
    expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(0)
  end

  it 'denies stale scope before receipt lookup without revealing prior receipt' do
    send_text
    integration.update!(destination_revision: 2)
    lookup
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).not_to have_key('message_id')
  end

  it 'does not adopt an old receipt when the current destination revision changes' do
    input = envelope
    send_text(input)
    integration.update!(destination_revision: 2)
    post "#{base}/receipts/#{input.fetch('broker_message_id')}", params: scope.merge('destination_revision' => 2,
                                                                                     'request_hash' => input.fetch('request_hash')),
                                                                 headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'protects proof identity and persisted message identity even from direct SQL updates' do
    send_text
    receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
    %w[request_hash conversation_id message_id state envelope published_at].each do |field|
      value = { 'request_hash' => 'a' * 64, 'conversation_id' => receipt.conversation_id + 1, 'message_id' => nil,
                'state' => 'MEDIA_PENDING', 'envelope' => {}, 'published_at' => 1.day.from_now }.fetch(field)
      expect do
        JrcBrokerLiveReceipt.transaction(requires_new: true) do
          JrcBrokerLiveReceipt.where(id: receipt.id).update_all(field => value) # rubocop:disable Rails/SkipsModelValidations
        end
      end.to raise_error(ActiveRecord::StatementInvalid, /JRC_LIVE_RECEIPT_IMMUTABLE/)
    end
  end

  it 'filters escrow and envelope in both request and SQL bind diagnostics' do
    filter = ActiveRecord::Base.inspection_filter
    expect(filter.filter_param('staged_bytes', 'synthetic-private')).to eq('[FILTERED]')
    expect(filter.filter_param('envelope', { content: 'synthetic-private' })).to eq('[FILTERED]')
    expect(Rails.application.config.filter_parameters).to include(:staged_bytes, :envelope)
  end

  it 'rejects physical Account, Inbox or Message deletion while retaining committed custody proof' do
    send_text
    receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
    [[Account, account.id], [Inbox, inbox.id], [Message, receipt.message_id]].each do |model, id|
      expect do
        model.transaction(requires_new: true) do
          model.where(id: id).delete_all
        end
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
    expect(receipt.reload.message).to be_present
    expect(account.reload).to be_persisted
    expect(inbox.reload).to be_persisted
  end

  it 'does not leak or write a cross-account conversation' do
    other = create(:conversation)
    other.update!(display_id: conversation.display_id + 99)
    send_text(seal(envelope.merge('conversation_id' => other.display_id)))
    expect(response).to have_http_status(:conflict)
    expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(0)
  end

  context 'with private durable media' do
    let(:bytes) { File.binread(Rails.root.join('spec/assets/sample.png')) }
    let(:media_input) do
      seal(envelope.merge('media' => { 'filename' => 'sample.png', 'mime_type' => 'image/png', 'byte_size' => bytes.bytesize,
                                       'sha256' => Digest::SHA256.hexdigest(bytes) }))
    end

    def reserve_media(input = media_input, asset: 'sample.png', mime: 'image/png')
      post "#{base}/messages", params: { envelope: input.to_json,
                                         file: Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', asset), mime) }, headers: headers
    end

    { 'sample.ogg' => 'audio/ogg', 'sample.pdf' => 'application/pdf', 'synthetic-opus.ogg' => 'audio/ogg' }.each do |asset, mime|
      it "verifies physical private #{mime} custody before publishing its native attachment" do
        expected = File.binread(Rails.root.join('spec/assets', asset))
        input = seal(media_input.merge('media' => { 'filename' => asset, 'mime_type' => mime, 'byte_size' => expected.bytesize,
                                                    'sha256' => Digest::SHA256.hexdigest(expected) }))
        reserve_media(input, asset: asset, mime: mime)
        expect(response).to have_http_status(:ok)
        receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
        JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
        expect(receipt.reload.state).to eq('PERSISTED')
        expect(Digest::SHA256.hexdigest(receipt.message.attachments.sole.file.download)).to eq(input.dig('media', 'sha256'))
      end
    end

    it 'escrows bytes before ACK, then publishes normal callbacks once after physical verification' do
      expect { reserve_media }.not_to change(Message, :count)
      expect(response).to have_http_status(:ok)
      pending = response.parsed_body
      expect(pending).to include('state' => 'MEDIA_PENDING', 'message_id' => nil)
      receipt = JrcBrokerLiveReceipt.find(pending.fetch('receipt_id'))
      expect(receipt.published_at).to be_nil
      expect(receipt.staged_bytes).to eq(bytes)
      clear_enqueued_jobs
      expect { JrcBroker::LiveIngressMediaJob.perform_now(receipt.id) }.to change(Message, :count).by(1)
      JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
      lookup(media_input)
      expect(response.parsed_body).to include('receipt_id' => pending.fetch('receipt_id'), 'state' => 'PERSISTED')
      message = Message.find(response.parsed_body.fetch('message_id'))
      expect(message.attachments.count).to eq(1)
      expect(Digest::SHA256.hexdigest(message.attachments.first.file.download)).to eq(media_input.dig('media', 'sha256'))
      expect(receipt.reload.staged_bytes).to be_nil
      expect(receipt.published_at).to be_present
    end

    it 'recovers the COMMIT to enqueue gap through its durable scheduler' do
      allow(JrcBroker::LiveIngressMediaJob).to receive(:perform_later).and_raise(IOError)
      reserve_media
      expect(response).to have_http_status(:ok)
      receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
      allow(JrcBroker::LiveIngressMediaJob).to receive(:perform_later).and_call_original
      clear_enqueued_jobs
      expect { JrcBroker::LiveIngressMediaSchedulerJob.perform_now }.to have_enqueued_job(JrcBroker::LiveIngressMediaJob).with(receipt.id)
    end

    it 'retains escrow and no message after outage, corruption or revoked original authority' do
      reserve_media
      receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
      allow(receipt.blob.service).to receive(:upload).and_raise(IOError)
      JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
      expect(receipt.reload).to have_attributes(state: 'MEDIA_PENDING', message_id: nil, staged_bytes: bytes)
      allow(receipt.blob.service).to receive(:upload).and_call_original
      receipt.blob.service.upload(receipt.blob.key, StringIO.new('corrupt'))
      JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
      expect(receipt.reload.state).to eq('MEDIA_PENDING')
      expect(receipt.blob.download).to eq('corrupt')
      admin.account_users.find_by!(account: account).update!(role: :agent)
      expect(receipt.blob.service).not_to receive(:download)
      JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
      expect(receipt.reload.message_id).to be_nil
    end

    it 'rejects wrong bytes before reserving an immutable intent' do
      reserve_media(seal(media_input.deep_merge('media' => { 'sha256' => 'f' * 64 })))
      expect(response).to have_http_status(:conflict)
      expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(0)
    end

    it 'rejects a foreign conversation before reserving media escrow or a private blob' do
      expect do
        reserve_media(seal(media_input.merge('conversation_id' => conversation.display_id + 99)))
      end.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:conflict)
      expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(0)
    end

    it 'does not reserve media escrow when an unproven generic message already has the source UUID' do
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       content_attributes: { 'jrc_broker_message_id' => media_input.fetch('broker_message_id') })
      clear_enqueued_jobs
      expect { reserve_media }.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:conflict)
      expect(JrcBrokerLiveReceipt.where(account: account)).to be_empty
      expect(enqueued_jobs).to be_empty
    end

    it 'retains pending custody without publication if a legacy generic message appears before the media executor' do
      reserve_media
      receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                       content_attributes: { 'jrc_broker_message_id' => media_input.fetch('broker_message_id') })
      clear_enqueued_jobs
      expect { JrcBroker::LiveIngressMediaJob.perform_now(receipt.id) }.not_to change(Message, :count)
      expect(receipt.reload).to have_attributes(state: 'MEDIA_PENDING', message_id: nil, staged_bytes: bytes)
      expect(receipt.last_error).to eq('JRC_INGRESS_LEGACY_UNPROVEN')
      expect(enqueued_jobs).to be_empty
    end

    it 'counts delayed media as unread only after custody publishes it, even if the agent visited during escrow' do
      reserve_media(seal(media_input.merge('occurred_at' => 1.day.ago.to_i)))
      receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
      conversation.update!(agent_last_seen_at: Time.current)
      expect(conversation.unread_incoming_messages).to be_empty
      JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
      expect(conversation.reload.unread_incoming_messages.size).to eq(1)
    end

    it 'enforces the per-account pending escrow budget before reserving another blob' do
      stub_const('JrcBroker::LiveIngressContract::MAX_PENDING_BYTES', bytes.bytesize * 2)
      reserve_media
      expect(response).to have_http_status(:ok)
      reserve_media(seal(media_input.merge('broker_message_id' => SecureRandom.uuid)))
      expect(response).to have_http_status(:ok)
      expect do
        reserve_media(seal(media_input.merge('broker_message_id' => SecureRandom.uuid)))
      end.not_to change(ActiveStorage::Blob, :count)
      expect(response).to have_http_status(:too_many_requests)
      expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(2)
    end

    it 'rechecks original token after storage work and keeps escrow when it rotates before commit' do
      reserve_media
      receipt = JrcBrokerLiveReceipt.find(response.parsed_body.fetch('receipt_id'))
      verifier = JrcBroker::LiveIngressMedia.new
      allow(JrcBroker::LiveIngressMedia).to receive(:new).and_return(verifier)
      allow(verifier).to receive(:store!).and_wrap_original do |method, *args|
        method.call(*args)
        admin.access_token.update!(token: SecureRandom.hex(24))
      end
      JrcBroker::LiveIngressMediaJob.perform_now(receipt.id)
      expect(receipt.reload).to have_attributes(state: 'MEDIA_PENDING', staged_bytes: bytes, message_id: nil)
      expect(receipt.blob.service.exist?(receipt.blob.key)).to be(true)
    end
  end
  # rubocop:enable RSpec/MultipleExpectations
end
