require 'rails_helper'

RSpec.describe 'Scoped direct Evolution WAID retry protection', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { 'https://evolution.example.test/chatwoot/webhook/direct-test' }
  let(:channel) { create(:channel_api, account: account, webhook_url: url) }
  let(:inbox) { channel.inbox }
  let(:message) { create(:message, account: account, inbox: inbox, message_type: :outgoing, sender: admin, source_id: 'WAID:fixture-key') }
  let(:path) { "/api/v1/accounts/#{account.id}/conversations/#{message.conversation.display_id}/messages/#{message.id}/retry" }
  let(:setting) { {'version'=>1,'account_id'=>account.id,'inbox_id'=>inbox.id,'origin'=>'https://group.example.test','webhook_url_sha256'=>Digest::SHA256.hexdigest(url)} }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return('https://group.example.test')
    message.update_columns(status: 'failed', content_attributes: {'external_error'=>'prior-diagnostic'})
  end

  it 'blocks the button and the normal authenticated retry without any stored receipt or send job' do
    channel.update!(additional_attributes: {Messages::DirectWaidRetryGuard::SETTING=>setting})
    expect(JrcBrokerWebhookObligation.exists?(message_id: message.id)).to be(false)
    expect(message.reload.display_content_attributes[Messages::DirectWaidRetryGuard::DISPLAY]).to be(true)
    expect { post path, headers: { api_access_token: admin.access_token.token }, as: :json }.not_to have_enqueued_job(SendReplyJob)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('JRC_DIRECT_WAID_RETRY_REQUIRES_RECONCILIATION')
    expect(message.reload).to be_failed
    expect(message.content_attributes.to_h).to eq({'external_error'=>'prior-diagnostic'})
    expect(message.source_id).to eq('WAID:fixture-key')
  end

  it 'preserves ordinary retry when this direct route has no opt-in, even with a client-supplied display flag' do
    message.update_columns(content_attributes: {Messages::DirectWaidRetryGuard::DISPLAY=>true})
    expect(message.reload.display_content_attributes).not_to include(Messages::DirectWaidRetryGuard::DISPLAY)
    expect { post path, headers: { api_access_token: admin.access_token.token }, as: :json }.to have_enqueued_job(SendReplyJob).with(message.id)
  end

  it 'refuses to apply a setting copied from another origin, account, inbox or webhook URL' do
    [{'origin'=>'https://another.example.test'}, {'account_id'=>account.id+1}, {'inbox_id'=>inbox.id+1}, {'webhook_url_sha256'=>'b'*64}].each do |change|
      channel.update!(additional_attributes: {Messages::DirectWaidRetryGuard::SETTING=>setting.merge(change)})
      expect(Messages::DirectWaidRetryGuard.applies?(message.reload)).to be(false)
    end
  end

  it 'accepts literal or percent-encoded parentheses only with the exact configured URL digest' do
    raw = 'https://evolution.example.test/chatwoot/webhook/Erik_Machado-(logistica)'
    encoded = raw.gsub('(', '%28').gsub(')', '%29')
    [raw, encoded].each do |endpoint|
      channel.update_columns(webhook_url: endpoint, additional_attributes: {
        Messages::DirectWaidRetryGuard::SETTING => setting.merge('webhook_url_sha256' => Digest::SHA256.hexdigest(endpoint))
      })
      post path, headers: { api_access_token: admin.access_token.token }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('JRC_DIRECT_WAID_RETRY_REQUIRES_RECONCILIATION')
    end
    channel.update_columns(webhook_url: raw)
    expect(Messages::DirectWaidRetryGuard.configured?(inbox.reload)).to be(false)
  end

  it 'rejects extra segments, controls, nested or malformed escapes even with a matching digest' do
    ['part/extra', 'part%2Fextra', 'part%5cextra', 'part%2528', 'part%0A', 'part%00', "part\n", 'part%2', 'part%zz', 'part%'].each do |segment|
      endpoint = "https://evolution.example.test/chatwoot/webhook/#{segment}"
      channel.update_columns(webhook_url: endpoint, additional_attributes: {
        Messages::DirectWaidRetryGuard::SETTING => setting.merge('webhook_url_sha256' => Digest::SHA256.hexdigest(endpoint))
      })
      expect(Messages::DirectWaidRetryGuard.configured?(inbox.reload)).to be(false), segment.inspect
    end
  end
end
