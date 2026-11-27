require 'rails_helper'

RSpec.describe 'Campaign connector isolation' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:phone) { '+5511999990001' }
  let(:asset) do
    account.jrc_campaign_media_assets.create!(kind: 'image',
                                              file: {
                                                io: File.open(Rails.root.join('spec/assets/avatar.png')), filename: 'synthetic.png', content_type: 'image/png'
                                              })
  end
  let(:step) do
    { 'kind' => 'template', 'template_name' => 'cloud_image', 'template_language' => 'pt_BR',
      'template_params' => { 'processed_params' => { 'header' => { 'media_type' => 'image', 'media_asset_id' => asset.id } } } }
  end

  around do |example|
    travel_to(Time.utc(2026, 11, 25, 15)) { example.run }
  end

  before do
    inbox
    channel.update!(message_templates: [{ 'name' => 'cloud_image', 'language' => 'pt_BR', 'status' => 'APPROVED',
                                          'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Synthetic invitation' }] }])
    JrcCampaigns::Consent.create!(account: account, recorded_by: user, phone_number: phone, granted_at: Time.current,
                                  evidence: 'Synthetic consent', purpose: 'whatsapp_campaigns')
    stub_request(:post, "https://graph.facebook.com/v24.0/#{channel.provider_config.fetch('phone_number_id')}/messages").with do |request|
      body = JSON.parse(request.body)
      body['type'] == 'template' && body.dig('template', 'components', 0, 'parameters', 0, 'type') == 'image'
    end.to_return(status: 200, body: { messages: [{ id: 'wamid.cloud-only', message_status: 'accepted' }] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })
  end

  it 'sends the individual image test only through Meta even when Evolution settings are invalid' do
    expect(JrcCampaigns::EvolutionConnector).not_to receive(:for).with(inbox)
    expect(JrcCampaigns::EvolutionClient).not_to receive(:new)
    expect(JrcCampaigns::EvolutionTestService).not_to receive(:new)
    expect(JrcCampaigns::BrokerConnector).not_to receive(:for).with(inbox)
    with_modified_env JRC_CAMPAIGNS_EVOLUTION_CONNECTORS: '{invalid' do
      result = JrcCampaigns::TestMessageService.new(account: account, user: user, inbox_id: inbox.id, phone_number: phone, step: step,
                                                    operator_confirmed: true, idempotency_key: SecureRandom.uuid).perform
      expect(result).to include(status: 'accepted', connector: 'official', message_id: 'wamid.cloud-only', delivery_confirmed: false)
    end
    expect(WebMock).to have_requested(:post, "https://graph.facebook.com/v24.0/#{channel.provider_config.fetch('phone_number_id')}/messages").once
  end

  it 'sends campaign images only through Meta and scopes delivery tracking to that inbox' do
    expect(JrcCampaigns::EvolutionConnector).not_to receive(:for).with(inbox)
    expect(JrcCampaigns::EvolutionClient).not_to receive(:new)
    expect(JrcCampaigns::EvolutionSafetyGate).not_to receive(:new)
    campaign = JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: user, name: 'Synthetic Cloud campaign',
                                              sending_window: { start: '00:00', end: '23:59', days: [0, 1, 2, 3, 4, 5, 6], timezone: 'UTC' })
    create(:contact, account: account, phone_number: phone)
    message_step = campaign.steps.create!(step)
    campaign.request_review!
    campaign.approve!(user, campaign.review_digest)
    recipient = JrcCampaigns::LaunchService.new(campaign).perform.recipients.sole
    JrcCampaigns::DispatchStepService.new(recipient: recipient, step: message_step).perform
    delivery = recipient.deliveries.sole
    expect(delivery.external_id).to eq('wamid.cloud-only')
    expect(delivery.metadata).not_to have_key('evolution_connector')
    expect(delivery.metadata).not_to have_key('broker_connector')
    JrcCampaigns::MetaStatusService.record(inbox: inbox, external_id: delivery.external_id, status: 'delivered')
    expect(delivery.reload).to be_delivered
  end

  it 'keeps a Meta rejection on the official route without falling back to Evolution or Broker' do
    expect(JrcCampaigns::EvolutionClient).not_to receive(:new)
    expect(JrcCampaigns::EvolutionConnector).not_to receive(:for).with(inbox)
    expect(JrcCampaigns::BrokerConnector).not_to receive(:for).with(inbox)
    stub_request(:post, "https://graph.facebook.com/v24.0/#{channel.provider_config.fetch('phone_number_id')}/messages")
      .to_return(status: 400, body: { error: { code: 132_012, type: 'OAuthException', message: 'private-synthetic-marker https://secret.example.test' } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
    result = JrcCampaigns::TestMessageService.new(account: account, user: user, inbox_id: inbox.id, phone_number: phone, step: step,
                                                  operator_confirmed: true, idempotency_key: SecureRandom.uuid).perform
    expect(result).to include(status: 'failed', connector: 'official', delivery_confirmed: false, error_code: '132012')
    record = JrcCampaigns::TestDelivery.find(result[:test_delivery_id])
    expect(record.failed_at).to be_present
    expect(record.metadata.dig('provider_response', 'error')).to eq('code' => '132012', 'type' => 'OAuthException')
    expect(record.error_message).not_to include('private-synthetic-marker', 'secret.example.test')
    expect(WebMock).not_to have_requested(:any, /evolution|broker/)
  end

  it 'fails closed instead of forwarding official campaigns to an alternate base URL' do
    expect(JrcCampaigns::EvolutionClient).not_to receive(:new)
    with_modified_env WHATSAPP_CLOUD_BASE_URL: 'https://evolution.example.test' do
      expect { JrcCampaigns::OfficialMetaRoute.assert!(inbox) }.to raise_error(ArgumentError, /API oficial/)
    end
  end

  it 'also rejects an alternate endpoint during native template synchronization without contacting Evolution' do
    expect(JrcCampaigns::EvolutionClient).not_to receive(:new)
    with_modified_env WHATSAPP_CLOUD_BASE_URL: 'https://evolution.example.test' do
      expect { channel.provider_service.load_templates! }.to raise_error(ArgumentError, /API oficial/)
    end
    expect(WebMock).not_to have_requested(:any, /evolution/)
  end

  it 'does not load or convert Meta templates for an Evolution API inbox' do
    api_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
    expect(Whatsapp::TemplateProcessorService).not_to receive(:new)
    expect { JrcCampaigns::TemplateConfiguration.new(inbox: api_inbox, step: step).validate! }.to raise_error(ArgumentError, /oficial/)
    expect(JrcCampaigns::MetaStatusService.record(inbox: api_inbox, external_id: 'wamid.cloud-only', status: 'read')).to be(false)
  end
end
