require 'rails_helper'

RSpec.describe 'WhatsApp Cloud retry containment', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     status: :failed, source_id: 'wamid.synthetic-original', content: 'Synthetic template',
                     content_attributes: { external_error: '131049: Synthetic restriction', in_reply_to_external_id: 'synthetic-parent',
                                           automation_rule_id: 42 },
                     additional_attributes: { template_params: { name: 'reativacao_cliente_01', language: 'pt_BR',
                                                                category: 'MARKETING', processed_params: { body: { '1' => 'Synthetic' } } } })
  end
  let(:retry_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/retry" }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    clear_enqueued_jobs
  end

  it 'R01 preserves the failed attempt and makes no HTTP request when source_id already exists' do
    original = message.reload.attributes.deep_dup
    perform_enqueued_jobs(only: SendReplyJob) do
      post retry_path, headers: agent.create_new_auth_token, as: :json
    end

    expect(performed_jobs.count { |job| job[:job] == SendReplyJob }).to eq(0)
    expect(message.reload.attributes).to eq(original)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('retry' => include('status' => 'blocked', 'reason' => 'marketing_restriction'))
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'R03 preserves an undeliverable destination failure' do
    message.update!(external_error: '131026: Synthetic undeliverable')
    original = message.reload.attributes.deep_dup
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('retry', 'reason')).to eq('destination_verification_required')
    expect(message.reload.attributes).to eq(original)
  end

  it 'blocks an uncertain failure without source_id instead of blindly repeating a possible POST' do
    message.update!(source_id: nil, external_error: 'Synthetic timeout')
    original = message.reload.attributes.deep_dup
    expect(SendReplyJob).not_to receive(:perform_later)
    2.times { post retry_path, headers: agent.create_new_auth_token, as: :json }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('retry', 'reason')).to eq('retry_unavailable')
    expect(message.reload.attributes).to eq(original)
  end

  it 'R09 leaves echo, private note and bot markers intact with no retry enqueue' do
    message.update!(private: true, content_attributes: message.content_attributes.merge('external_echo' => true, 'nico_delegation' => true))
    original = message.reload.attributes.deep_dup
    expect(SendReplyJob).not_to receive(:perform_later)
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(message.reload.attributes).to eq(original)
  end

  it 'R10 denies an unauthenticated caller' do
    post retry_path, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(message.reload).to be_failed
  end

  it 'R10 denies an agent without conversation access' do
    outsider = create(:user, account: account, role: :agent)
    post retry_path, headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(message.reload).to be_failed
  end

  it 'R10 denies a user from another account' do
    outsider = create(:user, account: create(:account), role: :administrator)
    post retry_path, headers: outsider.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(message.reload).to be_failed
  end
  it 'R10 denies a revoked application credential' do
    headers = agent.create_new_auth_token
    agent.update!(tokens: {})
    post retry_path, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(message.reload).to be_failed
  end

  it 'R11 keeps an existing synthetic attachment readable and preserves its IDs' do
    attachment = message.attachments.create!(account_id: account.id, file_type: :file,
                                             file: { io: StringIO.new('synthetic attachment'), filename: 'synthetic.txt', content_type: 'text/plain' })
    original_ids = [message.id, conversation.id, attachment.id, attachment.file.blob.id]
    original_checksum = attachment.file.blob.checksum
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect([message.reload.id, conversation.reload.id, attachment.reload.id, attachment.file.blob.id]).to eq(original_ids)
    expect(attachment.file.download).to eq('synthetic attachment')
    expect(attachment.file.blob.checksum).to eq(original_checksum)
  end

  it 'R09 keeps normal session delivery working with nullable historical metadata' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)
    legacy = create(:message, account: account, inbox: inbox, conversation: conversation,
                              message_type: :outgoing, source_id: nil, status: :sent, content: 'Synthetic legacy text')
    legacy.update_column(:additional_attributes, nil)
    request = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
              .to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-legacy' }] }.to_json,
                          headers: { 'Content-Type' => 'application/json' })
    SendReplyJob.perform_now(legacy.id)
    expect(request).to have_been_requested.once
    expect(legacy.reload.source_id).to eq('wamid.synthetic-legacy')
    expect(legacy.additional_attributes).to be_nil
  end

  it 'R09 keeps ordinary callbacks working with nullable historical metadata' do
    message.update_column(:additional_attributes, nil)
    callback = { entry: [{ changes: [{ value: { statuses: [{ id: message.source_id, status: 'delivered' }] } }] }] }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
    expect(message.reload).to be_delivered
  end

  it 'R11 keeps the message list readable with nullable historical metadata' do
    message.update_column(:additional_attributes, nil)
    get retry_path.sub("/#{message.id}/retry", ''), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').map { |item| item['id'] }).to include(message.id)
    expect(message.reload.additional_attributes).to be_nil
  end

  it 'returns a structured denial for legacy metadata without inventing a new attempt' do
    message.update!(sender: agent, content_attributes: { external_error: '130429: Synthetic limit' }, updated_at: 2.minutes.ago)
    message.update_column(:additional_attributes, nil)
    original = message.reload.attributes.deep_dup
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('retry', 'status')).to eq('blocked')
    expect(message.reload.attributes).to eq(original)
    expect(WhatsappRetryAttempt.where(original_message: message)).not_to exist
  end

  it 'R13 sends a normal pt_BR template through a real Redis queue and serialized Sidekiq wrapper, then handles its callback' do
    require 'sidekiq/api'
    channel.update!(message_templates: [{ name: 'reativacao_cliente_01', language: 'pt_BR', status: 'APPROVED',
                                         category: 'MARKETING', components: [{ type: 'BODY', text: 'Synthetic {{1}}' }] }])
    normal = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                              source_id: nil, content: 'Synthetic control', additional_attributes: message.additional_attributes)
    request = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages')
              .with do |http|
      body = JSON.parse(http.body)
      body['type'] == 'template' && body.dig('template', 'name') == 'reativacao_cliente_01' &&
        body.dig('template', 'language', 'code') == 'pt_BR' &&
        body.dig('template', 'components', 0, 'parameters', 0, 'text') == 'Synthetic'
    end.to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-control' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })

    original_adapter = SendReplyJob._queue_adapter
    original_test_adapter = SendReplyJob._test_adapter
    begin
      SendReplyJob.disable_test_adapter
      SendReplyJob.queue_adapter = :sidekiq
      Sidekiq::Testing.disable! do
        job = SendReplyJob.perform_later(normal.id)
        queued = Sidekiq::Queue.new(job.queue_name).find_job(job.provider_job_id)
        expect(queued).to be_present
        payload = queued.item['args'].first
        queued.delete
        ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper.new.perform(payload)
      end
    ensure
      SendReplyJob.queue_adapter = original_adapter
      SendReplyJob.enable_test_adapter(original_test_adapter)
    end
    expect(request).to have_been_requested.once
    expect(normal.reload.source_id).to eq('wamid.synthetic-control')
    expect(message.reload).to be_failed
    expect(message.source_id).to eq('wamid.synthetic-original')

    callback = { entry: [{ changes: [{ value: { statuses: [{ id: normal.source_id, status: 'delivered' }] } }] }] }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
    expect(normal.reload).to be_delivered
    expect(message.reload).to be_failed
  end
end
