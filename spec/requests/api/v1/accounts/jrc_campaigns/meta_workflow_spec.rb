require 'rails_helper'

RSpec.describe 'Meta campaign configuration and scope' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_campaigns" }
  let(:step) { { kind: 'template', template_name: 'approved', template_language: 'pt_BR', template_params: {} } }

  before do
    account.enable_features!('jrc_campaigns')
    inbox
    channel.update!(message_templates: [{ 'name' => 'approved', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                          'components' => [{ 'type' => 'BODY', 'text' => 'Synthetic' }] }])
  end

  it 'validates a template without persisting or sending a test' do
    expect do
      post "#{path}/campaigns/validate_message", params: { test_message: { inbox_id: inbox.id, step: step } }, headers: headers, as: :json
    end.not_to change(JrcCampaigns::TestDelivery, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('valid' => true, 'sent' => false)
    expect(WebMock).not_to have_requested(:post, /graph.facebook.com/)
  end

  it 'rejects a foreign inbox without loading its template or media' do
    other = create(:inbox)
    post "#{path}/metadata/template_media", params: { inbox_id: other.id, name: 'approved', language: 'pt_BR' }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects invalid media URLs without making an external request' do
    post "#{path}/media_assets", params: { kind: 'image', url: 'file:///etc/passwd', meta_template: true }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.jrc_campaign_media_assets).to be_empty
  end

  it 'returns the selected rows together with preview counts and pagination' do
    5.times do |index|
      phone = "+551199990000#{index}"
      create(:contact, account: account, phone_number: phone)
      JrcCampaigns::Consent.create!(account: account, phone_number: phone, purpose: 'whatsapp_campaigns', evidence: 'Synthetic authorization',
                                    recorded_by: admin, granted_at: Time.current)
    end
    post "#{path}/campaigns/audience_preview",
         params: { campaign: { inbox_id: inbox.id, audience_type: 'all_contacts' }, include_recipients: true, recipient_per_page: 2 }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data['estimated_recipients']).to eq(5)
    expect(data['recipients'].size).to eq(2)
    expect(data['recipient_pagination']).to include('total' => 5, 'total_pages' => 3)
  end

  it 'does not expose test history from another account' do
    other = create(:account)
    foreign = JrcCampaigns::TestDelivery.create!(account: other, inbox: create(:inbox, account: other), requested_by: admin,
                                                 idempotency_key: SecureRandom.uuid, phone_number: '+5511999990000', payload_digest: 'synthetic', status: 'unknown')
    get "#{path}/test_deliveries/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
