require 'rails_helper'

RSpec.describe 'Broker history synchronization V2', type: :request do
  # Acceptance cases correlate storage bytes, immutable receipts and zero live effects.
  # rubocop:disable RSpec/MultipleExpectations
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:organization) { SecureRandom.uuid }
  let(:integration) { SecureRandom.uuid }
  let(:instance) { SecureRandom.uuid }
  let(:owner) { SecureRandom.uuid }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_history_sync/v2/inboxes/#{inbox.id}" }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }
  let(:scope) do
    { organization_id: organization, integration_id: integration, instance_id: instance,
      destination_revision: 1, history_account_identity: owner }
  end
  let(:bootstrap) do
    scope.merge(broker_contact_id: SecureRandom.uuid, broker_conversation_id: SecureRandom.uuid,
                recipient: { kind: 'INDIVIDUAL', jid: '15550000001@s.whatsapp.net', name: 'Synthetic historical contact' },
                occurred_at: 5.days.ago.to_i, conversation_id: nil)
  end

  around do |example|
    previous_storage = ActiveStorage::Blob.service
    ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch('s3_compatible') if ENV['HISTORY_PHYSICAL_STORAGE_TEST'] == 'true'
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_HISTORY_SYNC_V2_ENABLED: 'true') { example.run }
  ensure
    ActiveStorage::Blob.service = previous_storage
  end

  before do
    account.enable_features!('jrc_broker')
    JrcBrokerIntegration.create!(account: account, organization_id: organization, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-decrypted')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration, instance_id: instance)
    headers
    clear_enqueued_jobs
  end

  it 'keeps media pending until physical bytes and the attachment are verified, recovering a lost upload acknowledgement' do
    path = Rails.root.join('spec/assets/sample.png')
    bytes = File.binread(path)
    metadata = { reference_id: SecureRandom.uuid, media_type: 'IMAGE', filename: 'synthetic.png', mime_type: 'image/png',
                 byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
    uploads = Array.new(2) do
      post "#{base}/media", params: { scope: scope.to_json, metadata: metadata.to_json,
                                      file: Rack::Test::UploadedFile.new(path, 'image/png') }, headers: headers
      expect(response).to have_http_status(:ok)
      response.parsed_body
    end
    expect(uploads.first).to eq(uploads.last)
    expect(uploads.first).to include('state' => 'STORED', 'sha256' => metadata.fetch(:sha256))
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    content = metadata.merge(type: 'MEDIA', caption: 'Synthetic historical caption')
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-MEDIA', content: content,
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'delivered')
    clear_enqueued_jobs
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    pending = response.parsed_body
    expect(pending).to include('state' => 'MEDIA_PENDING')
    intent = JrcBrokerHistoryMedia.find_by!(reference_id: metadata.fetch(:reference_id))
    JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
    JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
    get "#{base}/receipts/#{pending.fetch('receipt_id')}", params: scope, headers: headers
    expect(response.parsed_body).to include('state' => 'PERSISTED', 'media_sha256' => metadata.fetch(:sha256))
    stored = Message.find(pending.fetch('message_id'))
    expect(stored.attachments.count).to eq(1)
    expect(Digest::SHA256.hexdigest(stored.attachments.first.file.download)).to eq(metadata.fetch(:sha256))
    expect(stored).to have_attributes(content: 'Synthetic historical caption', created_at: Time.at(input.fetch(:occurred_at)).utc)
    expect(enqueued_jobs.map { |job| job.fetch(:job) }.uniq).to eq([JrcBroker::HistorySyncMediaJob])
  end

  it 'rejects truncated or altered media without issuing a physical custody receipt' do
    path = Rails.root.join('spec/assets/sample.png')
    bytes = File.binread(path)
    metadata = { reference_id: SecureRandom.uuid, media_type: 'IMAGE', filename: 'synthetic.png', mime_type: 'image/png',
                 byte_size: bytes.bytesize, sha256: 'f' * 64 }
    post "#{base}/media", params: { scope: scope.to_json, metadata: metadata.to_json,
                                    file: Rack::Test::UploadedFile.new(path, 'image/png') }, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(JrcBrokerHistoryMedia.where(account: account).count).to eq(0)
  end

  it 'recovers a missing private object and rechecks user revocation before completing historical media' do
    path = Rails.root.join('spec/assets/sample.png')
    bytes = File.binread(path)
    descriptor = { reference_id: SecureRandom.uuid, media_type: 'IMAGE', filename: 'synthetic.png', mime_type: 'image/png',
                   byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
    upload = lambda do
      post "#{base}/media", params: { scope: scope.to_json, metadata: descriptor.to_json,
                                      file: Rack::Test::UploadedFile.new(path, 'image/png') }, headers: headers
      expect(response).to have_http_status(:ok)
    end
    upload.call
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-RECOVERY', content: descriptor.merge(type: 'MEDIA', caption: 'Synthetic recovery'),
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'delivered')
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response.parsed_body).to include('state' => 'MEDIA_PENDING')
    intent = JrcBrokerHistoryMedia.find_by!(reference_id: descriptor.fetch(:reference_id))
    intent.blob.service.delete(intent.blob.key) # Deliberate loss of synthetic test bytes only.
    JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
    expect(intent.reload).to have_attributes(state: 'ATTACH_PENDING', attempts: 1)
    expect(intent.message.attachments).to be_empty
    upload.call
    account.account_users.find_by!(user: admin).update!(role: :agent)
    JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
    expect(intent.reload.state).to eq('ATTACH_PENDING')
    account.account_users.find_by!(user: admin).update!(role: :administrator)
    JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
    expect(intent.reload.state).to eq('READY')
    expect(intent.message.attachments.count).to eq(1)
    expect(Digest::SHA256.hexdigest(intent.message.attachments.first.file.download)).to eq(descriptor.fetch(:sha256))
  end

  it 'shows proven resolved history in a member personal inbox even when remote routing is unavailable, preserving exclusive queues' do
    create(:inbox_member, inbox: inbox, user: agent)
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    historical_id = response.parsed_body.fetch('conversation_id')
    url = "/api/v1/accounts/#{account.id}/conversations"
    %w[me mine_or_shared].each do |filter|
      get url, params: { assignee_type: filter, inbox_scope: 'member', status: 'all' }, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'payload').pluck('id')).to include(historical_id)
    end
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'connections' => {
                      inbox.id.to_s => { 'visibility' => 'assigned_only', 'supervisor_ids' => [admin.id] }
                    } } })
    get url, params: { assignee_type: 'me', inbox_scope: 'member', status: 'all' }, headers: agent.create_new_auth_token
    expect(response.parsed_body.dig('data', 'payload').pluck('id')).not_to include(historical_id)
  end

  it 'revokes personal history proof after a receipt is deleted without depending on model callbacks' do
    create(:inbox_member, inbox: inbox, user: agent)
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    retained = response.parsed_body.fetch('conversation_id')
    service = lambda {
      Conversations::SharedInboxScope.new(conversations: account.conversations, account: account, user: agent, member_inboxes_only: true)
    }
    before = service.call.metadata.fetch(:historical_proof_revisions).fetch(inbox.id.to_s)
    expect(service.call.perform.pluck(:display_id)).to include(retained)
    JrcBrokerHistoryReceipt.where(inbox: inbox, record_kind: 'CHAT').delete_all
    expect(service.call.metadata.fetch(:historical_proof_revisions).fetch(inbox.id.to_s)).not_to eq(before)
    expect(service.call.perform.pluck(:display_id)).not_to include(retained)
    expect { account.destroy! }.not_to raise_error
  end

  it 'rejects reacknowledging a stored intent after changing the destination revision' do
    path = Rails.root.join('spec/assets/sample.png')
    bytes = File.binread(path)
    descriptor = { reference_id: SecureRandom.uuid, media_type: 'IMAGE', filename: 'synthetic.png', mime_type: 'image/png',
                   byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
    upload = lambda { |revision|
      post "#{base}/media", params: { scope: scope.merge(destination_revision: revision).to_json, metadata: descriptor.to_json,
                                      file: Rack::Test::UploadedFile.new(path, 'image/png') }, headers: headers
    }
    upload.call(1)
    expect(response).to have_http_status(:ok)
    JrcBrokerIntegration.find_by!(account: account).update!(destination_revision: 2)
    upload.call(2)
    expect(response).to have_http_status(:conflict)
    expect(JrcBrokerHistoryMedia.find_by!(reference_id: descriptor.fetch(:reference_id))).to have_attributes(state: 'STORED', destination_revision: 1)
  end

  it 'does not inherit a replacement credential when the service token rotates on the same database row' do
    path = Rails.root.join('spec/assets/sample.png')
    bytes = File.binread(path)
    descriptor = { reference_id: SecureRandom.uuid, media_type: 'IMAGE', filename: 'synthetic.png', mime_type: 'image/png',
                   byte_size: bytes.bytesize, sha256: Digest::SHA256.hexdigest(bytes) }
    post "#{base}/media", params: { scope: scope.to_json, metadata: descriptor.to_json,
                                    file: Rack::Test::UploadedFile.new(path, 'image/png') }, headers: headers
    expect(response).to have_http_status(:ok)
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-TOKEN-ROTATION', content: descriptor.merge(type: 'MEDIA', caption: 'Synthetic token fence'),
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'delivered')
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response.parsed_body).to include('state' => 'MEDIA_PENDING')
    intent = JrcBrokerHistoryMedia.find_by!(reference_id: descriptor.fetch(:reference_id))
    token_id = admin.access_token.id
    admin.access_token.regenerate_token
    expect(admin.access_token.id).to eq(token_id)
    JrcBroker::HistorySyncMediaJob.perform_now(intent.id)
    expect(intent.reload.state).to eq('ATTACH_PENDING')
    expect(intent.message.attachments).to be_empty
  end

  it 'advertises only implemented categories behind an explicit gate and the current destination revision' do
    get base, params: scope, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('protocol' => 'jrc-history-sync/2', 'supports_text' => true,
                                            'supports_groups' => true, 'supports_media' => true, 'destination_revision' => 1)
    with_modified_env(JRC_HISTORY_SYNC_V2_ENABLED: 'false') do
      get base, params: scope, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'reuses a proven live contact and resolved conversation, without touching attendance or enqueuing callbacks' do
    contact = create(:contact, account: account, phone_number: '+15550000001')
    route = create(:contact_inbox, contact: contact, inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: route,
                                         status: :resolved, assignee: agent)
    before_state = conversation.reload.attributes
    input = bootstrap.merge(conversation_id: conversation.display_id)
    clear_enqueued_jobs
    receipts = Array.new(2) do
      post "#{base}/bootstrap", params: input, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      response.parsed_body
    end
    expect(receipts.first).to eq(receipts.last)
    expect(receipts.first).to include('state' => 'PERSISTED', 'conversation_id' => conversation.display_id, 'contact_id' => contact.id)
    expect(account.conversations.count).to eq(1)
    expect(conversation.reload.attributes).to eq(before_state)
    expect(enqueued_jobs).to be_empty
  end

  it 'creates a group as a group envelope, preserving participant identity and original outbound direction' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: 'a' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    route = response.parsed_body
    contact = account.contacts.find(route.fetch('contact_id'))
    expect(contact).to have_attributes(identifier: "jrc-group-#{'a' * 64}", phone_number: nil)
    expect(route.fetch('source_id')).to eq("jrc-group-#{'a' * 64}")
    conversation = account.conversations.find_by!(display_id: route.fetch('conversation_id'))
    incoming = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                           provider_message_id: 'SYNTHETIC-ONE', content: { type: 'TEXT', text: 'Archived group text' },
                           direction: 'incoming', participant_jid: '100000000000002@lid', occurred_at: input.fetch(:occurred_at), status: 'delivered')
    outgoing = incoming.merge(broker_message_id: SecureRandom.uuid, provider_message_id: 'SYNTHETIC-TWO', direction: 'outgoing', participant_jid: nil)
    [incoming, outgoing, incoming].each do |message|
      post "#{base}/messages", params: message, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('state' => 'PERSISTED', 'broker_message_id' => message.fetch(:broker_message_id))
    end
    expect(conversation.messages.where(message_type: :incoming).first.content_attributes)
      .to include('jrc_broker_participant_jid' => '100000000000002@lid')
    expect({ count: conversation.messages.count, status: conversation.reload.status, agent: conversation.assignee_id,
             team: conversation.team_id, jobs: enqueued_jobs }).to eq(count: 2, status: 'resolved', agent: nil, team: nil, jobs: [])
  end

  it 'returns the same durable message receipt after an acknowledgement is lost and rejects altered retries' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-ONE', content: { type: 'TEXT', text: 'Archived text' }, direction: 'outgoing',
                          participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'sent')
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    post "#{base}/messages", params: message.merge(status: 'read'), headers: headers, as: :json
    expect([response.status, response.parsed_body]).to eq([200, receipt])
    get "#{base}/receipts/#{receipt.fetch('receipt_id')}", params: scope, headers: headers
    expect([response.status, response.parsed_body]).to eq([200, receipt])
    post "#{base}/messages", params: message.merge(content: { type: 'TEXT', text: 'Changed text' }), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect({ count: account.messages.count, status: account.messages.first.status, jobs: enqueued_jobs })
      .to eq(count: 1, status: 'read', jobs: [])
  end

  it 'refuses stale destinations, cross-inbox, cross-tenant and ordinary agent requests before writing' do
    input = bootstrap
    [input.merge(destination_revision: 2), input.merge(organization_id: SecureRandom.uuid), input.merge(instance_id: SecureRandom.uuid)].each do |bad|
      expect { post "#{base}/bootstrap", params: bad, headers: headers, as: :json }.not_to change(Conversation, :count)
      expect(response).not_to have_http_status(:ok)
    end
    other_inbox = create(:channel_api, account: account).inbox
    post "/api/v1/accounts/#{account.id}/jrc_history_sync/v2/inboxes/#{other_inbox.id}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{base}/bootstrap", params: input, headers: { 'api_access_token' => agent.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'blocks ambiguous live mappings instead of creating another conversation and rejects unsupported media honestly' do
    contact = create(:contact, account: account, phone_number: '+15550000001')
    route = create(:contact_inbox, contact: contact, inbox: inbox)
    2.times { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: route) }
    input = bootstrap
    expect { post "#{base}/bootstrap", params: input, headers: headers, as: :json }.not_to change(Conversation, :count)
    expect(response).to have_http_status(:conflict)
    post "#{base}/messages", params: scope.merge(content: { type: 'MEDIA', url: 'https://invalid.example.test/private' }), headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects another owner reusing a conversation already bound by a durable receipt' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    display_id = response.parsed_body.fetch('conversation_id')
    expect do
      post "#{base}/bootstrap", params: input.merge(history_account_identity: SecureRandom.uuid, conversation_id: display_id), headers: headers,
                                as: :json
    end.not_to change(JrcBrokerHistoryReceipt, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'removes obsolete receipt metadata after an explicit message deletion instead of blocking existing deletion paths' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-DELETE', content: { type: 'TEXT', text: 'Synthetic deletable text' },
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'delivered')
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    expect { Message.where(id: receipt.fetch('message_id')).delete_all }.not_to raise_error
    get "#{base}/receipts/#{receipt.fetch('receipt_id')}", params: scope, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'refuses adoption with altered provider or group participant even when the display text and UUID match' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: 'b' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('conversation_id'))
    id = SecureRandom.uuid
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Synthetic live text', created_at: Time.at(input.fetch(:occurred_at)).utc,
                     content_attributes: { jrc_broker_message_id: id, jrc_broker_provider_message_id: 'SYNTHETIC-ORIGINAL',
                                           jrc_broker_participant_jid: '100000000000002@lid', jrc_broker_history_account_identity: owner })
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: id,
                          provider_message_id: 'SYNTHETIC-ORIGINAL', content: { type: 'TEXT', text: 'Synthetic live text' },
                          direction: 'incoming', participant_jid: '100000000000002@lid', occurred_at: input.fetch(:occurred_at), status: 'sent')
    clear_enqueued_jobs
    [message.merge(participant_jid: '100000000000003@lid'), message.merge(provider_message_id: 'SYNTHETIC-ALTERED')].each do |bad|
      expect { post "#{base}/messages", params: bad, headers: headers, as: :json }.not_to change(JrcBrokerHistoryReceipt, :count)
      expect(response).to have_http_status(:conflict)
    end
    expect(account.messages.count).to eq(1)
    expect(enqueued_jobs).to be_empty
  end

  it 'keeps an unproven legacy message blocked instead of assigning the current owner to it' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('conversation_id'))
    id = SecureRandom.uuid
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                     content: 'Synthetic legacy text', created_at: Time.at(input.fetch(:occurred_at)).utc,
                     content_attributes: { jrc_broker_message_id: id })
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: id,
                          provider_message_id: 'SYNTHETIC-LEGACY', content: { type: 'TEXT', text: 'Synthetic legacy text' },
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'sent')
    clear_enqueued_jobs
    expect { post "#{base}/messages", params: message, headers: headers, as: :json }.not_to change(JrcBrokerHistoryReceipt, :count)
    expect(response).to have_http_status(:conflict)
    expect(account.messages.count).to eq(1)
    expect(enqueued_jobs).to be_empty
  end

  it 'does not expose group contact metadata through global contact reads or search to an agent outside its inbox' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic private group', group_scope: 'c' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    contact_id = response.parsed_body.fetch('contact_id')
    agent_headers = agent.create_new_auth_token
    get "/api/v1/accounts/#{account.id}/contacts/#{contact_id}", headers: agent_headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{account.id}/contacts/search", params: { q: 'Synthetic private group' }, headers: agent_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to be_empty
    get "/api/v1/accounts/#{account.id}/contacts/#{contact_id}/conversations", headers: agent_headers
    expect(response).to have_http_status(:not_found)
    create(:inbox_member, inbox: inbox, user: agent)
    get "/api/v1/accounts/#{account.id}/contacts/#{contact_id}", headers: agent_headers
    expect(response).to have_http_status(:ok)
  end

  it 'refuses a different JID reusing an existing group scope or LID contact identifier' do
    [{ kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: 'd' * 64 },
     { kind: 'INDIVIDUAL', jid: '100000000000002@lid', name: 'Synthetic LID' }].each do |recipient|
      input = bootstrap.merge(recipient: recipient, broker_contact_id: SecureRandom.uuid, broker_conversation_id: SecureRandom.uuid)
      post "#{base}/bootstrap", params: input, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      display_id = response.parsed_body.fetch('conversation_id')
      suffix = recipient.fetch(:kind) == 'GROUP' ? '@g.us' : '@lid'
      altered = input.merge(broker_conversation_id: SecureRandom.uuid, conversation_id: display_id,
                            recipient: recipient.merge(jid: "100000000000003#{suffix}"))
      expect { post "#{base}/bootstrap", params: altered, headers: headers, as: :json }.not_to change(JrcBrokerHistoryReceipt, :count)
      expect(response).to have_http_status(:conflict)
    end
  end

  it 'does not overwrite a read receipt with a stale delivered status during replay' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-RACE', content: { type: 'TEXT', text: 'Synthetic status race' },
                          direction: 'outgoing', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'sent')
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    stale = account.messages.find(response.parsed_body.fetch('message_id'))
    Messages::StatusUpdateService.new(account.messages.find(stale.id), 'read').perform
    # Reproduce the query result captured immediately before another writer committed.
    allow_any_instance_of(JrcBrokerHistoryReceipt).to receive(:message).and_return(stale) # rubocop:disable RSpec/AnyInstance
    post "#{base}/messages", params: message.merge(status: 'delivered'), headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(stale.reload.status).to eq('read')
  end

  it 'does not expose group envelopes through global search or the customer directory' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic hidden group', group_scope: 'e' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    contact_id = response.parsed_body.fetch('contact_id')
    agent_headers = agent.create_new_auth_token
    %w[search/contacts search].each do |suffix|
      get "/api/v1/accounts/#{account.id}/#{suffix}", params: { q: 'Synthetic hidden group' }, headers: agent_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'contacts')).to be_empty
    end
    account.enable_features!('jrc_customer_master')
    get "/api/v1/accounts/#{account.id}/customers/contacts/#{contact_id}", headers: agent_headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{account.id}/customers/contacts", params: { q: 'Synthetic hidden group' }, headers: agent_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to be_empty
  end

  it 'preserves message receipts when an explicit normal contact merge moves a retained conversation' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    contact = account.contacts.find(response.parsed_body.fetch('contact_id'))
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: SecureRandom.uuid,
                          provider_message_id: 'SYNTHETIC-MERGE', content: { type: 'TEXT', text: 'Synthetic retained message' },
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'sent')
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    target = create(:contact, account: account, phone_number: '+15550000002')
    ContactMergeAction.new(account: account, base_contact: target, mergee_contact: contact).perform
    get "#{base}/receipts/#{receipt.fetch('receipt_id')}", params: scope, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('contact_id' => target.id, 'message_id' => receipt.fetch('message_id'))
    post "#{base}/messages", params: message, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.messages.count).to eq(1)
  end

  it 'rejects explicit merging of a group with a person instead of changing the recipient identity' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: 'f' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    group = account.contacts.find(response.parsed_body.fetch('contact_id'))
    person = create(:contact, account: account)
    expect { ContactMergeAction.new(account: account, base_contact: person, mergee_contact: group).perform }
      .to raise_error(JrcCustomers::MergePreserver::Conflict)
    expect(group.reload.identifier).to start_with('jrc-group-')
  end

  it 'does not let an agent manufacture access by linking a private group to another inbox' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: '1' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    contact_id = response.parsed_body.fetch('contact_id')
    other = create(:channel_api, account: account).inbox
    create(:inbox_member, inbox: other, user: agent)
    expect do
      post "/api/v1/accounts/#{account.id}/conversations", params: {
        inbox_id: other.id, contact_id: contact_id, source_id: 'synthetic-forbidden-group-link'
      }, headers: agent.create_new_auth_token, as: :json
    end.not_to change(Conversation, :count)
    expect(response).to have_http_status(:not_found)
    expect(ContactInbox.where(contact_id: contact_id, inbox_id: other.id)).not_to exist
  end

  it 'keeps a group envelope in its canonical inbox even when the caller belongs to both inboxes' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: '2' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    contact_id = response.parsed_body.fetch('contact_id')
    other = create(:channel_api, account: account).inbox
    [inbox, other].each { |box| create(:inbox_member, inbox: box, user: agent) }
    expect do
      post "/api/v1/accounts/#{account.id}/contacts/#{contact_id}/contact_inboxes", params: {
        inbox_id: other.id, source_id: 'synthetic-forbidden-group-copy'
      }, headers: agent.create_new_auth_token, as: :json
    end.not_to change(ContactInbox, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves shared customer contact reads for an ordinary agent with no inbox membership' do
    person = create(:contact, account: account, name: 'Synthetic shared customer', phone_number: '+15550000004')
    agent_headers = agent.create_new_auth_token
    get "/api/v1/accounts/#{account.id}/contacts/#{person.id}", headers: agent_headers
    expect(response).to have_http_status(:ok)
    get "/api/v1/accounts/#{account.id}/contacts/search", params: { q: person.name }, headers: agent_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to include(person.id)
    %w[search/contacts search].each do |suffix|
      get "/api/v1/accounts/#{account.id}/#{suffix}", params: { q: person.name }, headers: agent_headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'contacts').pluck('id')).to include(person.id)
    end
  end

  it 'keeps one canonical group link even when an agent requests another source in the same inbox' do
    input = bootstrap.merge(recipient: { kind: 'GROUP', jid: '100000000000001@g.us', name: 'Synthetic group', group_scope: '3' * 64 })
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    create(:inbox_member, inbox: inbox, user: agent)
    expect do
      post "/api/v1/accounts/#{account.id}/contacts/#{receipt.fetch('contact_id')}/contact_inboxes", params: {
        inbox_id: inbox.id, source_id: 'synthetic-second-source'
      }, headers: agent.create_new_auth_token, as: :json
    end.not_to change(ContactInbox, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    canonical = input.merge(broker_conversation_id: SecureRandom.uuid, conversation_id: receipt.fetch('conversation_id'))
    post "#{base}/bootstrap", params: canonical, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('source_id' => receipt.fetch('source_id'), 'contact_id' => receipt.fetch('contact_id'))
  end

  it 'adopts a matching message only when its complete source identity is already proven' do
    input = bootstrap
    post "#{base}/bootstrap", params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    conversation = account.conversations.find_by!(display_id: response.parsed_body.fetch('conversation_id'))
    id = SecureRandom.uuid
    stored = create(:message, account: account, inbox: inbox, conversation: conversation, sender: conversation.contact,
                              message_type: :incoming, content: 'Synthetic proven live text', created_at: Time.at(input.fetch(:occurred_at)).utc,
                              content_attributes: { jrc_broker_message_id: id, jrc_broker_provider_message_id: 'SYNTHETIC-PROVEN',
                                                    jrc_broker_participant_jid: nil, jrc_broker_history_account_identity: owner })
    old_message = stored.reload.attributes
    old_conversation = conversation.reload.attributes
    message = scope.merge(broker_conversation_id: input.fetch(:broker_conversation_id), broker_message_id: id,
                          provider_message_id: 'SYNTHETIC-PROVEN', content: { type: 'TEXT', text: 'Synthetic proven live text' },
                          direction: 'incoming', participant_jid: nil, occurred_at: input.fetch(:occurred_at), status: 'delivered')
    clear_enqueued_jobs
    2.times do
      post "#{base}/messages", params: message, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('message_id' => stored.id, 'state' => 'PERSISTED')
    end
    expect({ messages: account.messages.count, message: stored.reload.attributes, conversation: conversation.reload.attributes, jobs: enqueued_jobs })
      .to eq(messages: 1, message: old_message.merge('status' => 'delivered'), conversation: old_conversation, jobs: [])
  end
end
# rubocop:enable RSpec/MultipleExpectations
