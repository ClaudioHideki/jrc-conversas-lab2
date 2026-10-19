require 'rails_helper'

RSpec.describe 'Broker historical message import', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
  let(:organization) { SecureRandom.uuid }
  let(:integration) { SecureRandom.uuid }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/jrc_history_import" }
  let(:payload) do
    { organization_id: organization, integration_id: integration, inbox_id: inbox.id,
      broker_message_id: SecureRandom.uuid, content: 'Synthetic archived text', direction: 'incoming',
      occurred_at: 5.days.ago.to_i, status: 'delivered' }
  end

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!('jrc_broker')
    JrcBrokerIntegration.create!(account: account, organization_id: organization, broker_origin: 'https://broker.example.test',
                                 destination_revision: 1, encrypted_control_key: 'synthetic-not-decrypted')
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration, instance_id: SecureRandom.uuid)
  end

  it 'imports both directions once without reopening, updating attendance or scheduling delivery and automation' do
    headers = { 'api_access_token' => admin.access_token.token }
    before_state = conversation.reload.attributes
    inputs = [payload, payload.merge(direction: 'outgoing', status: 'read', broker_message_id: SecureRandom.uuid)]
    clear_enqueued_jobs
    inputs.each do |input|
      2.times do
        post path, params: input, headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include('protocol' => 'jrc-history-import/1', 'broker_message_id' => input[:broker_message_id])
      end
    end
    messages = conversation.messages.where("source_id LIKE 'jrc-history:%'").reorder(:id)
    expect(messages.map do |message|
      [message.message_type, message.status, message.created_at.to_i, message.content_attributes['jrc_broker_historical']]
    end).to eq(inputs.map { |input| [input[:direction], input[:status], input[:occurred_at], true] })
    expect(conversation.reload.attributes).to eq(before_state)
    expect(enqueued_jobs).to be_empty
  end

  it 'rejects altered retries and another company or inbox before writing' do
    input = payload
    headers = { 'api_access_token' => admin.access_token.token }
    post path, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    [[input.merge(content: 'Changed'), :conflict], [input.merge(organization_id: SecureRandom.uuid), :conflict],
     [input.merge(inbox_id: create(:channel_api).inbox.id), :not_found],
     [input.merge(integration_id: SecureRandom.uuid), :conflict]].each do |invalid, status|
      expect { post path, params: invalid, headers: headers, as: :json }.not_to change(Message, :count)
      expect(response).to have_http_status(status)
    end
  end

  it 'advances historical delivery status monotonically without emitting live update callbacks' do
    input = payload.merge(direction: 'outgoing', status: 'sent')
    headers = { 'api_access_token' => admin.access_token.token }
    conversation
    clear_enqueued_jobs
    %w[sent read delivered].each do |status|
      post path, params: input.merge(status: status), headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(conversation.messages.where("source_id LIKE 'jrc-history:%'").pluck(:status)).to eq(['read'])
    expect(enqueued_jobs).to be_empty
  end

  it 'refuses ordinary agents, revoked membership and disabled features' do
    input = payload
    post path, params: input, headers: { 'api_access_token' => agent.access_token.token }, as: :json
    expect(response).to have_http_status(:unauthorized)
    headers = { 'api_access_token' => admin.access_token.token }
    account.disable_features!('jrc_broker')
    post path, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    account.enable_features!('jrc_broker')
    admin.account_users.find_by!(account: account).destroy!
    post path, params: input, headers: headers, as: :json
    expect(response).not_to have_http_status(:ok)
  end

  it 'advertises only the configured account and inbox through the authenticated capability' do
    get "/api/v1/accounts/#{account.id}/jrc_history_import/inboxes/#{inbox.id}",
        params: { organization_id: organization, integration_id: integration }, headers: { 'api_access_token' => admin.access_token.token }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('protocol' => 'jrc-history-import/1', 'inbox_id' => inbox.id, 'supports_text' => true)
  end

  it 'creates an unmapped historical contact and conversation silently and returns the same scoped bootstrap receipt on retry' do
    path = "/api/v1/accounts/#{account.id}/jrc_history_import/inboxes/#{inbox.id}/bootstrap"
    input = { organization_id: organization, integration_id: integration, broker_contact_id: SecureRandom.uuid,
              broker_conversation_id: SecureRandom.uuid, phone: '15550000001', name: 'Synthetic historical contact', occurred_at: 5.days.ago.to_i }
    headers = { 'api_access_token' => admin.access_token.token }
    clear_enqueued_jobs
    receipts = 2.times.map do
      post path, params: input, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      response.parsed_body
    end
    expect(receipts.first).to eq(receipts.last)
    record = account.conversations.find_by!(display_id: receipts.first.fetch('conversation_id'))
    expect(record).to have_attributes(status: 'pending', assignee_id: nil, assignee_agent_bot_id: nil, team_id: nil)
    expect(record.created_at.to_i).to eq(input.fetch(:occurred_at))
    expect(account.contacts.where(phone_number: '+15550000001').count).to eq(1)
    expect(enqueued_jobs).to be_empty
    expect do
      post path, params: input.merge(organization_id: SecureRandom.uuid), headers: headers, as: :json
    end.not_to change(Conversation, :count)
    expect(response).not_to have_http_status(:ok)
  end
end
