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
end
