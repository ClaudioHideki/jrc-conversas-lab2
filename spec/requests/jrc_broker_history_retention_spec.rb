require 'rails_helper'

RSpec.describe 'Broker custody survives deletion requests', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:unprotected_conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:integration) do
    JrcBrokerIntegration.create!(account: account, organization_id: SecureRandom.uuid, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-unused')
  end
  let(:binding) { JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid) }
  let(:headers) { { 'api_access_token' => admin.access_token.token } }
  let(:receiver) { JrcBroker::LiveIngress.new(account: account, user: admin, access_token: admin.access_token) }
  let(:input) do
    { 'protocol' => 'jrc-live-ingress/1', 'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id,
      'instance_id' => binding.instance_id, 'destination_revision' => 1, 'broker_message_id' => SecureRandom.uuid,
      'conversation_id' => conversation.display_id, 'message_type' => 'incoming', 'message_origin' => 'LIVE',
      'content' => 'Synthetic retained custody', 'media' => nil }
  end
  let(:receipt) do
    result = receiver.receive(inbox.id, seal(input))
    JrcBrokerLiveReceipt.find(result.fetch('receipt_id'))
  end
  let(:bytes) { File.binread(Rails.root.join('spec/assets/sample.png')) }
  let(:pending) do
    media = { 'filename' => 'sample.png', 'mime_type' => 'image/png', 'byte_size' => bytes.bytesize,
              'sha256' => Digest::SHA256.hexdigest(bytes) }
    result = receiver.receive(inbox.id, seal(input.merge('media' => media)), StringIO.new(bytes))
    JrcBrokerLiveReceipt.find(result.fetch('receipt_id'))
  end

  around { |example| with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run } }

  before do
    account.enable_features!('jrc_broker')
    headers
  end

  def seal(value)
    canonical = lambda do |entry|
      next entry.keys.sort.index_with { |key| canonical.call(entry[key]) } if entry.is_a?(Hash)
      next entry.map { |item| canonical.call(item) } if entry.is_a?(Array)

      entry
    end
    value.merge('request_hash' => Digest::SHA256.hexdigest(JSON.generate(canonical.call(value))))
  end

  def expect_retained_error(&operation)
    expect(&operation).to raise_error { |error| expect(error.class.name).to eq('JrcBroker::HistoryRetention::Protected') }
  end

  it 'returns 409 before enqueueing inbox deletion even after the Broker feature is disabled' do
    receipt
    account.disable_features!('jrc_broker')
    clear_enqueued_jobs

    delete "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: headers, as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('code' => 'JRC_BROKER_HISTORY_RETAINED')
    expect(response.parsed_body.fetch('error')).to include('histórico')
    expect(enqueued_jobs).to be_empty
    expect(inbox.reload).to be_persisted
  end

  it 'returns 409 before enqueueing conversation deletion' do
    receipt
    clear_enqueued_jobs
    delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(enqueued_jobs).to be_empty
    expect(conversation.reload).to be_persisted
  end

  it 'does not redact the retained message through the generic DELETE endpoint' do
    original = receipt.message.attributes
    clear_enqueued_jobs
    delete "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{receipt.message_id}", headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(receipt.message.reload.attributes).to eq(original)
    expect(enqueued_jobs).to be_empty
  end

  it 'refuses contact deletion before its conversations or async dependencies are removed' do
    receipt
    clear_enqueued_jobs
    delete "/api/v1/accounts/#{account.id}/contacts/#{conversation.contact_id}", headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(conversation.contact.reload).to be_persisted
    expect(enqueued_jobs).to be_empty
  end

  %i[account inbox].each do |target|
    it "revalidates an existing #{target} deletion job before deleting even an unprotected sibling" do
      protected = receipt
      object = public_send(target)
      clear_enqueued_jobs
      expect_retained_error { DeleteObjectJob.perform_now(object) }
      expect(unprotected_conversation.reload).to be_persisted
      expect(conversation.reload).to be_persisted
      expect(protected.reload.message.reload).to be_persisted
      expect(enqueued_jobs).to be_empty
    end
  end

  %i[account inbox conversation].each do |target|
    it "also refuses direct #{target} destruction before dependent callbacks" do
      receipt
      clear_enqueued_jobs
      expect_retained_error { public_send(target).destroy! }
      expect(unprotected_conversation.reload).to be_persisted
      expect(conversation.reload).to be_persisted
      expect(enqueued_jobs).to be_empty
    end
  end

  it 'keeps pending LIVE bytes, its reserved blob and conversation when no message exists yet' do
    protected = pending
    clear_enqueued_jobs
    expect_retained_error { DeleteObjectJob.perform_now(conversation) }
    expect(protected.reload).to have_attributes(state: 'MEDIA_PENDING', message_id: nil, staged_bytes: bytes)
    expect(protected.blob.reload).to be_persisted
    expect(conversation.reload).to be_persisted
    expect(enqueued_jobs).to be_empty
  end

  it 'preserves the attachment row and its private bytes on direct attachment destruction' do
    protected = pending
    JrcBroker::LiveIngressMediaJob.perform_now(protected.id)
    attachment = protected.reload.message.attachments.sole
    clear_enqueued_jobs
    expect_retained_error { attachment.destroy! }
    expect(attachment.reload.file.download).to eq(bytes)
    expect(enqueued_jobs).to be_empty
  end

  it 'preserves the storage attachment when purge is invoked directly' do
    protected = pending
    JrcBroker::LiveIngressMediaJob.perform_now(protected.id)
    attachment = protected.reload.message.attachments.sole
    expect_retained_error { attachment.file.purge }
    expect(attachment.reload.file).to be_attached
    expect(attachment.file.download).to eq(bytes)
  end

  it 'refuses direct blob purge while durable escrow owns its reserved key' do
    protected = pending
    expect_retained_error { protected.blob.purge }
    expect(protected.blob.reload).to be_persisted
    expect(protected.reload.staged_bytes).to eq(bytes)
  end

  it 'retains V2-only custody despite its legacy cascading foreign keys' do
    proof = JrcBrokerHistoryReceipt.create!(account: account, inbox: inbox, contact: conversation.contact, conversation: conversation,
                                             receipt_id: SecureRandom.uuid, organization_id: SecureRandom.uuid, integration_id: SecureRandom.uuid,
                                             history_account_identity: SecureRandom.uuid, source_id: SecureRandom.uuid,
                                             broker_conversation_id: SecureRandom.uuid, record_kind: 'CHAT', request_hash: 'a' * 64,
                                             recipient: { 'kind' => 'INDIVIDUAL', 'jid' => '123@lid' }, created_at: Time.current)
    clear_enqueued_jobs
    expect_retained_error { DeleteObjectJob.perform_now(inbox) }
    expect(proof.reload).to be_persisted
    expect(unprotected_conversation.reload).to be_persisted
    expect(enqueued_jobs).to be_empty
  end

  it 'keeps a V2 media reservation before any CHAT or MESSAGE receipt exists' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'sample.png', content_type: 'image/png')
    reservation = JrcBrokerHistoryMedia.create!(account: account, inbox: inbox, blob: blob, organization_id: SecureRandom.uuid,
                                                integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid,
                                                history_account_identity: SecureRandom.uuid, reference_id: SecureRandom.uuid,
                                                destination_revision: 1, descriptor: {}, descriptor_hash: 'a' * 64,
                                                access_token_sha256: 'b' * 64, state: 'RESERVED')
    clear_enqueued_jobs
    expect_retained_error { DeleteObjectJob.perform_now(inbox) }
    expect(reservation.reload).to have_attributes(state: 'RESERVED', message_id: nil)
    expect(blob.download).to eq(bytes)
    expect(enqueued_jobs).to be_empty
  end

  it 'does not block a different account with the same conversation display id' do
    receipt
    other = create(:conversation)
    other.update!(display_id: conversation.display_id)
    DeleteObjectJob.perform_now(other)
    expect(Conversation.exists?(other.id)).to be(false)
    expect(conversation.reload).to be_persisted
  end

  it 'keeps normal inbox deletion available without Broker custody' do
    DeleteObjectJob.perform_now(inbox)
    expect(Inbox.exists?(inbox.id)).to be(false)
    expect(Conversation.exists?(unprotected_conversation.id)).to be(false)
  end
end
