require 'rails_helper'

RSpec.describe 'WhatsApp Cloud eligible retry', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
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
end
