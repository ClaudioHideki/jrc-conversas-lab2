require 'rails_helper'

RSpec.describe 'Broker campaign transport', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:origin) { 'https://broker.example.test' }
  let(:integration_id) { SecureRandom.uuid }
  let(:instance_id) { SecureRandom.uuid }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account, webhook_url: "#{origin}/v1/integrations/chatwoot/#{integration_id}/events")) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999000') }
  let(:prefix) { "#{origin}/v1/integrations/chatwoot/control" }
  let(:transport) do
    { protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, instanceId: instance_id, inboxId: inbox.id,
      destinationRevision: 1, identityRevision: 2, numberSuffix: '0000', ready: true, reason: nil }
  end
  let(:campaign) { JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Synthetic Broker campaign') }
  let(:step) { campaign.steps.create!(kind: 'text', body: 'Synthetic message', position: 0) }
  let(:execution) { campaign.executions.create!(run_number: 1, status: 'running') }
  let(:recipient) { execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact, phone_number: contact.phone_number, destination: contact.phone_number) }
  let(:service) { JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step) }

  around do |example|
    with_modified_env('JRC_BROKER_ENABLED' => 'true', 'JRC_BROKER_ALLOWED_ORIGINS' => origin, 'FRONTEND_URL' => 'https://central.example.test',
                      'JRC_BROKER_CREDENTIAL_KEY' => Base64.strict_encode64('s' * 32)) { example.run }
  end
  before do
    account.enable_features!('jrc_broker', 'jrc_campaigns')
    ciphertext = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-scoped-key')
    JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: SecureRandom.uuid, destination_revision: 1, encrypted_control_key: ciphertext)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: instance_id)
    stub_request(:get, "#{prefix}/context").to_return(headers: { 'Content-Type' => 'application/json' },
      body: { organizationId: JrcBrokerIntegration.find_by!(account: account).organization_id, accountId: account.id, destinationRevision: 1, chatwootOrigin: 'https://central.example.test' }.to_json)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(headers: { 'Content-Type' => 'application/json' }, body: transport.to_json)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(headers: { 'Content-Type' => 'application/json' }, body: {}.to_json)
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: contact.phone_number, evidence: 'Synthetic fixture authorization', purpose: 'whatsapp_campaigns', granted_at: Time.current)
  end

  it 'lists a scoped Broker inbox without credentials and leaves unrelated API inboxes out' do
    other = create(:inbox, account: account, channel: create(:channel_api, account: account))
    get "/api/v1/accounts/#{account.id}/jrc_campaigns/metadata", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch('whatsapp_inboxes')
    expect(rows.map { |r| r['id'] }).to include(inbox.id)
    expect(rows.map { |r| r['id'] }).not_to include(other.id)
    expect(rows.find { |r| r['id'] == inbox.id }).to include('connector' => 'broker', 'health_error' => false)
    expect(response.body).not_to include('synthetic-scoped-key', 'encrypted_control_key')
  end

  it 'keeps an older Broker visible but unavailable without the campaign protocol' do
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(status: 404)
    get "/api/v1/accounts/#{account.id}/jrc_campaigns/metadata", headers: admin.create_new_auth_token
    row = response.parsed_body.fetch('whatsapp_inboxes').find { |r| r['id'] == inbox.id }
    expect(row).to include('health_error' => true, 'setup_reason' => 'BROKER_UPDATE_OR_CONFIGURATION_REQUIRED')
  end

  it 'shows the existing direct Evolution inbox as requiring explicit configuration instead of assuming it is a Broker sender' do
    direct = create(:inbox, account: account, channel: create(:channel_api, account: account, webhook_url: 'https://direct.example.test/chatwoot/webhook/synthetic'))
    get "/api/v1/accounts/#{account.id}/jrc_campaigns/metadata", headers: admin.create_new_auth_token
    row = response.parsed_body.fetch('whatsapp_inboxes').find { |r| r['id'] == direct.id }
    expect(row).to include('connector' => 'evolution', 'health_error' => true, 'setup_reason' => 'DIRECT_EVOLUTION_CONFIGURATION_REQUIRED')
    expect(JrcCampaigns::Campaign.new(account: account).accepts_sending_inbox?(direct)).to be(false)
  end

  it 'rejects cross-account and changed callbacks' do
    other = create(:account)
    expect(JrcCampaigns::Campaign.new(account: other).accepts_sending_inbox?(inbox)).to be(false)
    inbox.channel.update!(webhook_url: 'https://elsewhere.example.test/events')
    expect { JrcCampaigns::BrokerConnector.for(inbox).transport(admin) }.to raise_error(JrcBroker::Client::Error, 'JRC_BROKER_CALLBACK_MISMATCH')
  end

  context 'approved delivery' do
    before do
      step
      campaign.request_review!
      campaign.approve!(admin, campaign.review_digest)
      campaign.update!(status: 'running')
    end

    it 'uses the selected list without requiring or inventing a separate positive consent record' do
      JrcCampaigns::Consent.where(account: account, phone_number: contact.phone_number).delete_all
      expect(JrcCampaigns::AudienceResolver.new(campaign).entries.map(&:phone_number)).to include(contact.phone_number)
      expect { service.perform }.not_to change(JrcCampaigns::Consent, :count)
      expect(recipient.deliveries.sole.status).to eq('sending')
      expect(account.messages.count).to eq(1)
    end

    it 'creates one legitimate automation message and waits for actual provider evidence before advancing' do
      2.times { service.perform }
      delivery = recipient.deliveries.sole
      expect(delivery).to have_attributes(status: 'sending', sent_at: nil)
      message = account.messages.find(delivery.metadata.fetch('message_id'))
      expect(message).to have_attributes(sender: admin, private: false)
      expect(message.additional_attributes).to include('campaign_id' => campaign.id, 'jrc_campaign_broker' => true)
      expect(message.additional_attributes).not_to have_key('jrc_campaign_evolution')
      expect(account.messages.where("additional_attributes->>'jrc_campaign_id' = ?", campaign.id.to_s).count).to eq(1)
      expect(recipient.reload).to be_processing
      receipt_url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
      receipt = { protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, conversationId: message.conversation.display_id, messageId: message.id }
      stub_request(:get, receipt_url).to_return(headers: { 'Content-Type' => 'application/json' }, body: receipt.merge(status: 'queued').to_json)
      JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id)
      expect(delivery.reload.sent_at).to be_nil
      stub_request(:get, receipt_url).to_return(headers: { 'Content-Type' => 'application/json' }, body: receipt.merge(status: 'read').to_json)
      2.times { JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id) }
      expect(delivery.reload.attributes.slice('status', 'error_message', 'metadata')).to include('status' => 'read')
      expect(delivery.sent_at).to be_present
      expect(recipient.reload).to be_read
      expect(campaign.reload).to be_completed
      expect(account.messages.where("additional_attributes->>'jrc_campaign_id' = ?", campaign.id.to_s).count).to eq(1)
    end

    it 'does not send after consent revocation' do
      JrcCampaigns::Consent.where(account: account).update_all(revoked_at: Time.current)
      service.perform
      expect(recipient.deliveries.sole).to be_skipped
      expect(account.messages.count).to eq(0)
    end

    it 'queues reconciliation from a confirmed native webhook but never accepts a local status as provider evidence' do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.find(delivery.metadata.fetch('message_id'))
      expect { Messages::StatusUpdateService.new(message, 'sent').perform }
        .to have_enqueued_job(JrcCampaigns::BrokerStatusJob).with('campaign', delivery.id)
      expect(delivery.reload.sent_at).to be_nil
      expect(recipient.reload).to be_processing
    end

    it 'pauses an uncertain dispatch and never creates another native message on replay' do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.find(delivery.metadata.fetch('message_id'))
      url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
      stub_request(:get, url).to_return(headers: { 'Content-Type' => 'application/json' }, body: { protocol: 'chatwoot-campaigns/v1', integrationId: integration_id,
        conversationId: message.conversation.display_id, messageId: message.id, status: 'queued' }.to_json)
      JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id, 19)
      expect(delivery.reload).to be_unknown
      expect(campaign.reload).to be_paused
      service.perform
      expect(account.messages.count).to eq(1)
      expect(recipient.reload.sent_at).to be_nil
    end

    it 'does not count a receipt from a different conversation' do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.find(delivery.metadata.fetch('message_id'))
      url = "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
      stub_request(:get, url).to_return(headers: { 'Content-Type' => 'application/json' }, body: { protocol: 'chatwoot-campaigns/v1', integrationId: integration_id,
        conversationId: message.conversation.display_id + 1, messageId: message.id, status: 'read' }.to_json)
      JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id)
      expect(delivery.reload.sent_at).to be_nil
      expect(recipient.reload).to be_processing
    end

    it 'invalidates approval when the confirmed sender identity changes' do
      stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(headers: { 'Content-Type' => 'application/json' }, body: transport.merge(identityRevision: 3).to_json)
      service.perform
      expect(recipient.deliveries.sole).to be_skipped
      expect(account.messages.count).to eq(0)
    end

    it 'keeps Broker-owned automations protected' do
      stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(headers: { 'Content-Type' => 'application/json' }, body: transport.merge(ready: false, reason: 'CAMPAIGN_EXECUTOR_EXTERNAL_REQUIRED').to_json)
      service.perform
      expect(recipient.deliveries.sole).to be_failed
      expect(account.messages.count).to eq(0)
    end
  end

  it 'claims a test idempotently without reporting a local message as provider sent' do
    options = { account: account, user: admin, phone_number: contact.phone_number, inbox_id: inbox.id, step: { kind: 'text', body: 'Synthetic test' }, idempotency_key: SecureRandom.uuid, operator_confirmed: true }
    first = JrcCampaigns::TestMessageService.new(**options).perform
    second = JrcCampaigns::TestMessageService.new(**options).perform
    expect(first).to eq(second)
    expect(first).to include(status: 'sending', delivery_confirmed: false)
    expect(account.messages.count).to eq(1)
    expect(JrcCampaigns::TestDelivery.where(account: account).count).to eq(1)
  end

  it 'does not allow a test without explicit confirmation or revoked consent' do
    options = { account: account, user: admin, phone_number: contact.phone_number, inbox_id: inbox.id, step: { kind: 'text', body: 'Synthetic test' }, idempotency_key: SecureRandom.uuid }
    expect { JrcCampaigns::TestMessageService.new(**options).perform }.to raise_error(ArgumentError, /Confirme/)
    JrcCampaigns::Consent.where(account: account).update_all(revoked_at: Time.current)
    expect { JrcCampaigns::TestMessageService.new(**options, operator_confirmed: true).perform }.to raise_error(ArgumentError, /Consentimento/)
    expect(account.messages.count).to eq(0)
    expect(JrcCampaigns::TestDelivery.where(account: account).count).to eq(0)
  end

  it 'uses an attachment owned by the account without requesting its storage URL' do
    asset = JrcCampaigns::MediaAsset.create!(account: account, created_by: admin, kind: 'document',
      file: { io: StringIO.new('%PDF-1.4 synthetic fixture'), filename: 'fixture.pdf', content_type: 'application/pdf' })
    result = JrcCampaigns::TestMessageService.new(account: account, user: admin, phone_number: contact.phone_number, inbox_id: inbox.id,
      step: { kind: 'document', body: 'Synthetic attachment', media_asset_id: asset.id, media_url: 'https://storage.example.test/not-requested' },
      idempotency_key: SecureRandom.uuid, operator_confirmed: true).perform
    delivery = JrcCampaigns::TestDelivery.find(result.fetch(:test_delivery_id))
    message = account.messages.find(delivery.metadata.fetch('message_id'))
    expect(message.attachments.sole.file.blob).to eq(asset.file.blob)
    expect(a_request(:get, 'https://storage.example.test/not-requested')).not_to have_been_made
  end

  it 'rejects a media asset belonging to another Account' do
    other = create(:account)
    asset = JrcCampaigns::MediaAsset.create!(account: other, kind: 'document', file: { io: StringIO.new('%PDF-1.4 synthetic'), filename: 'fixture.pdf', content_type: 'application/pdf' })
    expect do
      JrcCampaigns::TestMessageService.new(account: account, user: admin, phone_number: contact.phone_number, inbox_id: inbox.id,
        step: { kind: 'document', media_asset_id: asset.id }, idempotency_key: SecureRandom.uuid, operator_confirmed: true).perform
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.messages.count).to eq(0)
    expect(JrcCampaigns::TestDelivery.where(account: account).count).to eq(0)
  end

  it 'rejects private-network media without creating a message or leaking its URL' do
    expect do
      JrcCampaigns::TestMessageService.new(account: account, user: admin, phone_number: contact.phone_number, inbox_id: inbox.id,
        step: { kind: 'document', media_url: 'http://127.0.0.1/private.pdf' }, idempotency_key: SecureRandom.uuid, operator_confirmed: true).perform
    end.to raise_error(ArgumentError, /mídia pública/)
    expect(account.messages.count).to eq(0)
    expect(JrcCampaigns::TestDelivery.where(account: account).count).to eq(0)
  end
end
