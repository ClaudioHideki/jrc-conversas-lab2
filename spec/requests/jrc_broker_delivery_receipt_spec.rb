require 'rails_helper'

RSpec.describe 'Broker provider delivery receipt', type: :request do
  let(:account) { create(:account) }
  let(:message) { create(:message, account: account, inbox: inbox, message_type: :outgoing) }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}" }
  let(:proof) { { version: 1, canonical_message_id: SecureRandom.uuid, provider_message_id: 'synthetic-provider', state: 'SENT' } }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }

  before do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end

  it 'accepts a provider receipt from the current account administrator API token' do
    patch path, params: { status: 'sent', broker_delivery: proof }, headers: { api_access_token: admin.access_token.token }, as: :json
    expect(response).to have_http_status(:success)
    expect(message.reload.content_attributes['jrc_broker_outbound']).to include(proof.stringify_keys)
  end

  it 'serializes an old queued message as unconfirmed without adding any durable intent metadata' do
    message.update!(content_attributes: {})
    obligation = JrcBrokerWebhookObligation.find_by!(message_id: message.id)
    payload = obligation.payload.deep_dup
    get path.delete_suffix("/#{message.id}"), params: { after: message.id, before: message.id + 1 },
                                              headers: { api_access_token: admin.access_token.token }, as: :json
    expect(response).to have_http_status(:success)
    rendered = response.parsed_body.fetch('payload').find { |row| row['id'] == message.id }
    expect(rendered.dig('content_attributes', 'jrc_broker_legacy_unconfirmed')).to be(true)
    expect(rendered['content_attributes']).not_to have_key('jrc_broker_outbound')
    expect(message.reload.content_attributes).to eq({})
    expect(obligation.reload.payload).to eq(payload)
  end

  it 'projects legacy conversation previews without an obligation lookup for each rendered preview' do
    message.update!(content_attributes: {})
    queries = []
    ActiveSupport::Notifications.subscribed(lambda { |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      queries << sql if sql.include?('FROM "jrc_broker_webhook_obligations"') && !sql.include?('FROM "messages"')
    }, 'sql.active_record') do
      get "/api/v1/accounts/#{account.id}/conversations", params: { status: 'all' },
                                                       headers: { api_access_token: admin.access_token.token }, as: :json
    end
    expect(response).to have_http_status(:success)
    rendered = response.parsed_body.fetch('data').fetch('payload').find { |row| row['id'] == message.conversation.display_id }
    expect(rendered.dig('messages', 0, 'content_attributes', 'jrc_broker_legacy_unconfirmed')).to be(true)
    expect(rendered.dig('last_non_activity_message', 'content_attributes', 'jrc_broker_legacy_unconfirmed')).to be(true)
    expect(queries).to be_empty
    expect(message.reload.content_attributes).to eq({})
  end

  it 'rejects provider evidence supplied by an ordinary agent' do
    create(:inbox_member, inbox: inbox, user: agent)
    patch path, params: { status: 'sent', broker_delivery: proof }, headers: { api_access_token: agent.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(message.reload.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('PENDING')
  end

  it 'rejects a malformed receipt instead of silently treating it as an ordinary status callback' do
    patch path, params: { status: 'sent', broker_delivery: proof.merge(provider_message_id: nil) },
                headers: { api_access_token: admin.access_token.token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(message.reload.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('PENDING')
  end

  it 'preserves an ordinary API status callback without manufacturing provider evidence' do
    patch path, params: { status: 'sent' }, headers: { api_access_token: admin.access_token.token }, as: :json
    expect(response).to have_http_status(:success)
    expect(message.reload.content_attributes.dig('jrc_broker_outbound', 'state')).to eq('PENDING')
  end

  it 'rejects a scalar receipt without raising a server error' do
    patch path, params: { status: 'sent', broker_delivery: 'invalid' }, headers: { api_access_token: admin.access_token.token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  %w[sent failed].each do |late_status|
    it "keeps a confirmed read receipt when a legacy #{late_status} callback arrives late" do
      receipt = proof.stringify_keys.merge('state' => 'READ')
      JrcBroker::OutboundReceipt.new(message, status: 'read', proof: receipt).perform
      original = message.reload.content_attributes.deep_dup
      patch path, params: { status: late_status, external_error: 'SYNTHETIC_LATE_CALLBACK' },
                  headers: { api_access_token: admin.access_token.token }, as: :json
      expect(response).to have_http_status(:success)
      expect(message.reload).to be_read
      expect(message.content_attributes).to eq(original)
    end
  end

  it 'requires new provider proof before replacing a confirmed send with a failure' do
    JrcBroker::OutboundReceipt.new(message, status: 'sent', proof: proof.stringify_keys).perform
    original = message.reload.content_attributes.deep_dup
    patch path, params: { status: 'failed', external_error: 'SYNTHETIC_UNPROVEN_FAILURE' },
                headers: { api_access_token: admin.access_token.token }, as: :json
    expect(response).to have_http_status(:success)
    expect(message.reload).to be_sent
    expect(message.content_attributes).to eq(original)
  end

  it 'blocks generic retry of a durable Broker reply without erasing uncertainty or enqueueing another send' do
    message.update!(status: :failed, content_attributes: message.content_attributes.merge(
      'jrc_broker_delivery' => { 'version' => 1, 'outcome' => 'unknown', 'uncertain' => true }, 'retained' => 'synthetic'
    ))
    original = message.content_attributes.deep_dup
    clear_enqueued_jobs
    expect do
      post "#{path}/retry", headers: { api_access_token: admin.access_token.token }, as: :json
    end.not_to have_enqueued_job(SendReplyJob)
    expect(response).to have_http_status(:conflict)
    expect(message.reload).to be_failed
    expect(message.content_attributes).to eq(original)
    expect(JrcBrokerWebhookObligation.where(message_id: message.id).count).to eq(1)
  end
end
