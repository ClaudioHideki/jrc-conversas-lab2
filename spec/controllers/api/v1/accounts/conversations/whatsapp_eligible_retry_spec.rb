require 'rails_helper'

RSpec.describe 'WhatsApp Cloud eligible retry', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { api_key: 'test_key', phone_number_id: '123456789', business_account_id: 'synthetic-business' })
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:template) { { name: 'synthetic_retry', language: 'pt_BR', category: 'MARKETING', processed_params: { body: { '1' => 'Synthetic' } } } }
  let!(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, sender: agent,
                     message_type: :outgoing, status: :failed, source_id: 'wamid.synthetic-rejected',
                     content: 'Synthetic template', content_attributes: { external_error: '130429: Synthetic rate limit' },
                     additional_attributes: { template_params: template }, updated_at: 2.minutes.ago)
  end
  let(:retry_path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages/#{message.id}/retry" }

  before do
    create(:inbox_member, user: agent, inbox: inbox)
    channel.update!(message_templates: [{ name: 'synthetic_retry', language: 'pt_BR', status: 'APPROVED',
                                         category: 'MARKETING', components: [{ type: 'BODY', text: 'Synthetic {{1}}' }] }])
    clear_enqueued_jobs
  end

  it 'R04 durably queues one related attempt while preserving the original rejection' do
    original = message.reload.attributes.deep_dup
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.dig('retry', 'status')).to eq('queued')
    expect(response.parsed_body.dig('retry', 'original_message_id')).to eq(message.id)
    expect(response.parsed_body.dig('retry', 'attempt_id')).to be_present
    expect(message.reload.attributes).to eq(original)
    expect(enqueued_jobs.none? { |job| job[:job] == SendReplyJob }).to be(true)
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'R05 returns the same attempt for two clicks, even with different request keys' do
    2.times do |index|
      post retry_path, params: { idempotency_key: "synthetic-#{index}" }, headers: agent.create_new_auth_token, as: :json
    end
    expect(response.parsed_body.dig('retry', 'status')).to eq('already_requested')
    expect(WhatsappRetryAttempt.where(original_message: message).count).to eq(1)
    expect(WhatsappRetryAttempt.last.message.reload).to be_failed
  end

  it 'R08 keeps the durable obligation when Redis enqueue fails' do
    allow(WhatsappRetryJob).to receive(:perform_later).and_raise(Redis::CannotConnectError)
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:accepted)
    attempt = WhatsappRetryAttempt.find(response.parsed_body.dig('retry', 'attempt_id'))
    expect(attempt.state).to eq('queued')
    allow(WhatsappRetryJob).to receive(:perform_later).and_call_original
    WhatsappRetryRecoveryJob.perform_now
    expect(enqueued_jobs).to include(hash_including(job: WhatsappRetryJob, args: [attempt.id]))
  end


  it 'R12 exposes the persisted attempt state and original link after reloading the message list' do
    post retry_path, headers: agent.create_new_auth_token, as: :json
    child_id = response.parsed_body.dig('retry', 'message_id')
    get retry_path.sub("/#{message.id}/retry", ''), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    child = response.parsed_body.fetch('payload').find { |item| item['id'] == child_id }
    expect(child.fetch('status')).to eq('failed')
    expect(child.dig('additional_attributes', 'whatsapp_retry', 'state')).to eq('queued')
    expect(child.dig('additional_attributes', 'whatsapp_retry', 'original_message_id')).to eq(message.id)
  end

  it 'rejects incomplete template parameters before reserving any attempt' do
    params = message.additional_attributes['template_params'].deep_dup
    params['processed_params'] = { 'body' => {} }
    message.update!(additional_attributes: { template_params: params }, updated_at: 2.minutes.ago)
    post retry_path, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(WhatsappRetryAttempt.where(original_message: message)).not_to exist
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'preserves the exact numeric parameter sequence for twelve reversed input keys' do
    values = (1..12).to_a.reverse.to_h { |index| [index.to_s, "Synthetic#{index}"] }
    params = message.additional_attributes['template_params'].deep_dup
    params['processed_params'] = { 'body' => values }
    message.update!(additional_attributes: { template_params: params }, updated_at: 2.minutes.ago)
    data = channel.message_templates.first.deep_dup
    data['components'] = [{ 'type' => 'BODY', 'text' => (1..12).map { |index| "{{#{index}}}" }.join(' ') }]
    channel.update!(message_templates: [data])
    stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return(
      status: 200, body: { data: [data] }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    request = stub_request(:post, 'https://graph.facebook.com/v13.0/123456789/messages').with do |http|
      JSON.parse(http.body).dig('template', 'components', 0, 'parameters').map { |item| item['text'] } == (1..12).map { |index| "Synthetic#{index}" }
    end.to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-twelve' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
    original = message.reload.attributes.deep_dup
    post retry_path, headers: agent.create_new_auth_token, as: :json
    WhatsappRetryJob.perform_now(WhatsappRetryAttempt.last.id)
    expect(request).to have_been_requested.once
    expect(message.reload.attributes).to eq(original)
  end

  it 'recovers a known provider identifier after a crash before final state persistence without another POST' do
    post retry_path, headers: agent.create_new_auth_token, as: :json
    attempt = WhatsappRetryAttempt.last
    attempt.update!(state: 'submitting', updated_at: 20.minutes.ago)
    attempt.message.update!(source_id: 'wamid.synthetic-already-accepted')
    WhatsappRetryRecoveryJob.perform_now
    expect(attempt.reload.state).to eq('accepted')
    expect(attempt.message.reload).to be_sent
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'backs off a validation timeout while preserving the pending obligation' do
    post retry_path, headers: agent.create_new_auth_token, as: :json
    attempt = WhatsappRetryAttempt.last
    request = stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_timeout
    2.times { WhatsappRetryJob.perform_now(attempt.id) }
    expect(attempt.reload.state).to eq('queued')
    expect(attempt.next_attempt_at).to be > Time.current
    expect(request).to have_been_requested.once
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  context 'when processing the queued attempt' do
    let(:post_url) { "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages" }
    let(:template_data) { channel.reload.message_templates }

    before do
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return(
        status: 200, body: { data: template_data }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      post retry_path, headers: agent.create_new_auth_token, as: :json
    end

    it 'R04/R05 submits the serialized retry once and records the new correlation' do
      attempt = WhatsappRetryAttempt.last
      request = stub_request(:post, post_url).with do |http|
        body = JSON.parse(http.body)
        body['type'] == 'template' && body.dig('template', 'language', 'code') == 'pt_BR' &&
          body.dig('template', 'components', 0, 'parameters', 0, 'text') == 'Synthetic'
      end.to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-retry' }] }.to_json,
                    headers: { 'Content-Type' => 'application/json' })
      payload = WhatsappRetryJob.new(attempt.id).serialize
      2.times { ActiveJob::Base.execute(payload) }
      expect(request).to have_been_requested.once
      expect(attempt.reload.state).to eq('accepted')
      expect(attempt.message.reload).to be_sent
      expect(attempt.message.source_id).to eq('wamid.synthetic-retry')
      expect(message.reload.source_id).to eq('wamid.synthetic-rejected')
      expect(message).to be_failed
    end

    it 'R06 does not resubmit after a timeout following possible provider acceptance' do
      attempt = WhatsappRetryAttempt.last
      request = stub_request(:post, post_url).to_timeout
      2.times { WhatsappRetryJob.perform_now(attempt.id) }
      WhatsappRetryRecoveryJob.perform_now
      expect(request).to have_been_requested.once
      expect(attempt.reload.state).to eq('unknown')
      expect(attempt.message.reload).to be_failed
      expect(attempt.message.additional_attributes.dig('whatsapp_retry', 'state')).to eq('unknown')
    end

    it 'R06 treats malformed success as unknown, not as confirmed rejection' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:post, post_url).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('unknown')
    end

    it 'records a confirmed Meta rejection with its real numeric code' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:post, post_url).to_return(status: 400, body: { error: { code: 131049, message: 'Synthetic restriction' } }.to_json,
                                            headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('failed')
      expect(attempt.message.reload.external_error).to start_with('131049:')
      expect(message.reload.external_error).to start_with('130429:')
    end

    it 'R10 rechecks actor access before POST' do
      attempt = WhatsappRetryAttempt.last
      InboxMember.where(inbox: inbox, user: agent).destroy_all
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('cancelled')
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it 'R10 denies a revoked Meta credential at processing time' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return(status: 401, body: '{}')
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('cancelled')
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it 'rechecks current Meta template approval before submission' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return(
        status: 200, body: { data: [] }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('cancelled')
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it 'R07 retains an early callback and never regresses read to delivered or sent' do
      attempt = WhatsappRetryAttempt.last
      early = { entry: [{ changes: [{ value: { statuses: [{ id: 'wamid.synthetic-early', status: 'read' }] } }] }] }.with_indifferent_access
      request = stub_request(:post, post_url).to_return do
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: early).perform
        { status: 200, body: { messages: [{ id: 'wamid.synthetic-early' }] }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
      WhatsappRetryJob.perform_now(attempt.id)
      expect(request).to have_been_requested.once
      expect(attempt.reload.state).to eq('read')
      expect(attempt.message.reload).to be_read
      %w[delivered sent failed].each do |status|
        early[:entry][0][:changes][0][:value][:statuses][0][:status] = status
        Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: early).perform
      end
      expect(attempt.message.reload).to be_read
      expect(message.reload).to be_failed
    end

    it 'R07 refuses to update a retry through the callback of another inbox' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:post, post_url).to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-scoped' }] }.to_json,
                                            headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      other = create(:channel_whatsapp, account: create(:account), provider: 'whatsapp_cloud',
                                       sync_templates: false, validate_provider_config: false)
      callback = { entry: [{ changes: [{ value: { statuses: [{ id: 'wamid.synthetic-scoped', status: 'delivered' }] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: other.inbox, params: callback).perform
      expect(attempt.message.reload).to be_sent
      expect(attempt.reload.state).to eq('accepted')
    end

    it 'preserves a pending obligation through a transient validation outage and sends only after validation recovers' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return(status: 503, body: '{}')
      request = stub_request(:post, post_url).to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-after-validation' }] }.to_json,
                                                      headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('queued')
      expect(attempt.next_attempt_at).to be > Time.current
      expect(request).not_to have_been_requested
      attempt.update!(next_attempt_at: 1.second.ago)
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return(
        status: 200, body: { data: template_data }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      perform_enqueued_jobs(only: WhatsappRetryJob) { WhatsappRetryRecoveryJob.perform_now }
      expect(attempt.reload.state).to eq('accepted')
      expect(request).to have_been_requested.once
    end

    it 'does not submit if another process marks the attempt unknown during preflight' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return do
        attempt.update!(state: 'unknown')
        { status: 200, body: { data: template_data }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end
      request = stub_request(:post, post_url).to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-stopped' }] }.to_json,
                                                      headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      expect(request).not_to have_been_requested
      expect(attempt.reload.state).to eq('unknown')
    end

    it 'requires a new correlation instead of accepting the original source_id again' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:post, post_url).to_return(status: 200, body: { messages: [{ id: message.source_id }] }.to_json,
                                            headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('unknown')
      expect(attempt.message.reload.source_id).to be_nil
      expect(message.reload.source_id).to eq('wamid.synthetic-rejected')
    end

    it 'keeps a server error after POST uncertain without a second submission' do
      attempt = WhatsappRetryAttempt.last
      request = stub_request(:post, post_url).to_return(status: 503, body: { error: { code: 131016 } }.to_json,
                                                      headers: { 'Content-Type' => 'application/json' })
      2.times { WhatsappRetryJob.perform_now(attempt.id) }
      expect(attempt.reload.state).to eq('unknown')
      expect(request).to have_been_requested.once
    end

    it 'rechecks a destination change before submission' do
      attempt = WhatsappRetryAttempt.last
      conversation.contact_inbox.update!(source_id: 'BR.SYNTHETICOTHER')
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('cancelled')
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it 'does not let a stale validator cancel a submission owned by another worker' do
      attempt = WhatsappRetryAttempt.last
      stub_request(:get, %r{https://graph.facebook.com/v14.0/.*/message_templates}).to_return do
        attempt.update!(state: 'submitting')
        attempt.message.update!(source_id: 'wamid.synthetic-other-owner')
        { status: 401, body: '{}', headers: { 'Content-Type' => 'application/json' } }
      end
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('submitting')
      Whatsapp::RetryReceiptService.reconcile!(attempt)
      expect(attempt.reload.state).to eq('accepted')
      expect(attempt.message.reload).to be_sent
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it 'ignores an old sent callback on the failed original while processing its queued retry' do
      attempt = WhatsappRetryAttempt.last
      callback = { entry: [{ changes: [{ value: { statuses: [{ id: message.source_id, status: 'sent' }] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
      expect(message.reload).to be_failed
      request = stub_request(:post, post_url).to_return(status: 200, body: { messages: [{ id: 'wamid.synthetic-after-old-sent' }] }.to_json,
                                                      headers: { 'Content-Type' => 'application/json' })
      WhatsappRetryJob.perform_now(attempt.id)
      expect(attempt.reload.state).to eq('accepted')
      expect(request).to have_been_requested.once
    end

    it 'suppresses an unnecessary retry after the original is truly delivered' do
      attempt = WhatsappRetryAttempt.last
      callback = { entry: [{ changes: [{ value: { statuses: [{ id: message.source_id, status: 'delivered' }] } }] }] }.with_indifferent_access
      Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
      WhatsappRetryJob.perform_now(attempt.id)
      expect(message.reload).to be_delivered
      expect(attempt.reload.state).to eq('cancelled')
      expect(a_request(:post, post_url)).not_to have_been_made
    end

    it 'R08 never reclaims a stale submission for another POST' do
      attempt = WhatsappRetryAttempt.last
      attempt.update!(state: 'submitting', updated_at: 20.minutes.ago)
      WhatsappRetryRecoveryJob.perform_now
      expect(attempt.reload.state).to eq('unknown')
      WhatsappRetryJob.perform_now(attempt.id)
      expect(a_request(:post, post_url)).not_to have_been_made
    end
  end
end
