require 'rails_helper'

# The signed transport and native campaign records are intentionally exercised together.
RSpec.describe JrcCampaigns::BrokerDeliveryFailure do # rubocop:disable RSpec/MultipleMemoizedHelpers
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:origin) { 'https://broker.example.test' }
  let(:integration_id) { SecureRandom.uuid }
  let(:instance_id) { SecureRandom.uuid }
  let(:callback) { "#{origin}/v1/integrations/chatwoot/#{integration_id}/events" }
  let(:prefix) { "#{origin}/v1/integrations/chatwoot/control" }
  let(:channel) { create(:channel_api, account: account, webhook_url: callback) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999000') }
  let(:campaign) { JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Synthetic failure', status: 'running') }
  let(:step) { campaign.steps.create!(kind: 'text', body: 'Synthetic body', position: 0) }
  let(:execution) { campaign.executions.create!(run_number: 1, status: 'running') }
  let(:recipient) do
    execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact, phone_number: contact.phone_number,
                                 destination: contact.phone_number, status: 'processing')
  end
  let(:connector) { JrcCampaigns::BrokerConnector.for(inbox) }
  let(:delivery) do
    recipient.deliveries.create!(inbox: inbox, step: step, status: 'sending', metadata: { 'broker_connector' => connector.public_configuration })
  end
  let(:message) do
    attributes = { 'campaign_id' => campaign.id.to_s, 'jrc_campaign_id' => campaign.id, 'jrc_campaign_broker_delivery_id' => delivery.id }
    JrcCampaigns::BrokerMessageSender.call(delivery: delivery, user: admin, phone_number: contact.phone_number,
                                           step: { 'kind' => 'text', 'body' => step.body }, attributes: attributes)
  end
  let(:payload) { message.webhook_data.merge(event: 'message_created') }
  let(:delivery_id) { SecureRandom.uuid }
  let(:intent_id) { SecureRandom.uuid }
  let(:receipt_url) do
    "#{prefix}/connections/#{integration_id}/conversations/#{message.conversation.display_id}/campaign-messages/#{message.id}"
  end

  around do |example|
    with_modified_env('JRC_BROKER_ENABLED' => 'true', 'JRC_BROKER_ALLOWED_ORIGINS' => origin, 'FRONTEND_URL' => 'https://central.example.test',
                      'JRC_BROKER_CREDENTIAL_KEY' => Base64.strict_encode64('s' * 32)) { example.run }
  end

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('broker.example.test').and_return(['93.184.216.34'])
    account.enable_features!('jrc_broker', 'jrc_campaigns')
    ciphertext = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-private-key')
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: SecureRandom.uuid,
                                               destination_revision: 1, encrypted_control_key: ciphertext)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: instance_id)
    context_response = {
      organizationId: integration.organization_id, accountId: account.id, destinationRevision: 1, chatwootOrigin: 'https://central.example.test'
    }
    stub_request(:get, "#{prefix}/context").to_return(headers: { 'Content-Type' => 'application/json' }, body: context_response.to_json)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(headers: { 'Content-Type' => 'application/json' }, body: '{}')
    transport_response = {
      protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, instanceId: instance_id, inboxId: inbox.id,
      destinationRevision: 1, identityRevision: 2, ownerRevision: 0, numberSuffix: '0000', ready: true, reason: nil
    }
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport")
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: transport_response.to_json)
    intent_response = {
      protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', expiresAt: 5.minutes.from_now.iso8601, replayed: false
    }
    stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return(
      status: 201, headers: { 'Content-Type' => 'application/json' }, body: intent_response.to_json
    )
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: contact.phone_number,
                                  evidence: 'Synthetic fixture authorization', purpose: 'whatsapp_campaigns', granted_at: Time.current)
    message
    stub_request(:get, receipt_url).to_return(headers: { 'Content-Type' => 'application/json' }, body: {
      protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, conversationId: message.conversation.display_id,
      messageId: message.id, status: 'queued'
    }.to_json)
    clear_enqueued_jobs
  end

  after do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'propagates a permanent callback refusal and stops misleading receipt polling without another message' do
    request = stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_failed
    expect(recipient.reload).to be_failed
    expect(campaign.reload).to be_paused
    expect(delivery.metadata.fetch('broker_failure')).to include('outcome' => 'rejected', 'phase' => 'callback', 'http_status' => 403)
    clear_enqueued_jobs
    JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id)
    expect(a_request(:get, receipt_url)).not_to have_been_made
    expect(account.messages.count).to eq(1)
    expect(request).to have_been_requested.once
  end

  it 'records the intent phase and refusal status without posting the unsigned callback' do
    stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return(status: 409)
    request = stub_request(:post, callback).to_return(status: 200)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_failed
    expect(message.reload.content_attributes.fetch('jrc_broker_delivery')).to include(
      'phase' => 'campaign_intent', 'http_status' => 409, 'error_class' => 'JrcBroker::Client::Error', 'outcome' => 'rejected'
    )
    expect(request).not_to have_been_requested
    expect(recipient.reload).to be_failed
  end

  it 'treats a callback context mismatch as a refusal before dispatch' do
    request = stub_request(:post, callback).to_return(status: 200)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: 'obsolete-private-secret', delivery_id: delivery_id)
    expect(delivery.reload).to be_failed
    expect(message.reload.content_attributes.fetch('jrc_broker_delivery')).to include(
      'phase' => 'validate', 'error_class' => 'JrcBroker::WebhookDelivery::ContextChanged', 'outcome' => 'rejected'
    )
    expect(request).not_to have_been_requested
  end

  it 'retains a prior callback timeout when a subsequent attempt is permanently refused' do
    stub_request(:post, callback).to_timeout
    expect do
      Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    end.to raise_error(JrcBroker::WebhookDelivery::Unavailable)
    stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_unknown
    expect(delivery.metadata.fetch('broker_failure')).to include('outcome' => 'unknown', 'http_status' => 403)
    expect(recipient.reload.failed_at).to be_nil
    expect(campaign.reload).to be_paused
    expect(account.messages.count).to eq(1)
  end

  it 'retains an incomplete callback attempt even if the process stopped before recording its error' do
    message.update!(content_attributes: { 'jrc_broker_delivery' => { 'version' => 1, 'in_flight' => true } })
    stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_unknown
    expect(campaign.reload).to be_paused
  end

  it 'does not turn a previously accepted callback into proof of non-delivery' do
    message.update!(content_attributes: { 'jrc_broker_delivery' => { 'version' => 1, 'accepted' => true } })
    stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_unknown
    expect(recipient.reload.failed_at).to be_nil
  end

  it 'keeps a legacy generic rejection unknown and stops polling without replay' do
    Messages::StatusUpdateService.new(message, 'failed', 'JRC_BROKER_DELIVERY_REJECTED').perform
    clear_enqueued_jobs
    JrcCampaigns::BrokerStatusJob.perform_now('campaign', delivery.id)
    expect(delivery.reload).to be_unknown
    expect(recipient.reload.failed_at).to be_nil
    expect(campaign.reload).to be_paused
    expect(a_request(:get, receipt_url)).not_to have_been_made
    expect(enqueued_jobs).to be_empty
  end

  it 'keeps an exhausted transient failure unknown rather than a confirmed rejection' do
    stub_request(:post, callback).to_timeout
    perform_enqueued_jobs(only: WebhookJob) do
      WebhookJob.perform_later(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    end
    expect(delivery.reload).to be_unknown
    expect(recipient.reload.failed_at).to be_nil
    expect(campaign.reload).to be_paused
    expect(message.reload.external_error).to eq('JRC_BROKER_DELIVERY_UNAVAILABLE')
    expect(message.content_attributes.fetch('jrc_broker_delivery')).to include('phase' => 'callback', 'outcome' => 'unknown')
  end

  %w[sent delivered read unknown].each do |state|
    it "preserves an existing #{state} delivery after a late local refusal" do
      attributes = { status: state, error_message: state == 'unknown' ? 'Earlier uncertainty' : nil }
      attributes[:sent_at] = Time.current unless state == 'unknown'
      attributes[:delivered_at] = Time.current if %w[delivered read].include?(state)
      attributes[:read_at] = Time.current if state == 'read'
      delivery.update!(attributes)
      original = delivery.attributes.slice('status', 'sent_at', 'delivered_at', 'read_at', 'failed_at', 'error_message')
      stub_request(:post, callback).to_return(status: 403)
      Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
      expect(delivery.reload.attributes.slice(*original.keys)).to eq(original)
      expect(message.reload).not_to be_failed unless state == 'unknown'
    end
  end

  it 'preserves a replied recipient while recording a failed step' do
    recipient.update!(status: 'replied', replied_at: Time.current)
    stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_failed
    expect(recipient.reload).to be_replied
    expect(campaign.reload).to be_paused
  end

  it 'does not affect a foreign delivery when its ID appears in message attributes' do
    foreign_account = create(:account)
    foreign_campaign = JrcCampaigns::Campaign.create!(account: foreign_account, name: 'Foreign campaign', status: 'running')
    foreign_step = foreign_campaign.steps.create!(kind: 'text', body: 'Foreign', position: 0)
    foreign_execution = foreign_campaign.executions.create!(run_number: 1, status: 'running')
    foreign_recipient = foreign_execution.recipients.create!(campaign: foreign_campaign, phone_number: '+5511888888000',
                                                             destination: '+5511888888000')
    foreign_delivery = foreign_recipient.deliveries.create!(inbox: create(:inbox, account: foreign_account), step: foreign_step, status: 'sending')
    message.update!(additional_attributes: message.additional_attributes.merge('jrc_campaign_broker_delivery_id' => foreign_delivery.id))
    Webhooks::Trigger.execute(callback, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                              secret: channel.secret, delivery_id: delivery_id)
    expect(delivery.reload).to be_sending
    expect(foreign_delivery.reload).to be_sending
    expect(foreign_campaign.reload).to be_running
    expect(campaign.reload).to be_running
  end

  it 'leaves an ordinary broker conversation outside campaign reconciliation' do
    message.update!(additional_attributes: {})
    stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                              secret: channel.secret, delivery_id: delivery_id)
    expect(message.reload).to be_failed
    expect(message.content_attributes).not_to have_key('jrc_broker_delivery')
    expect(delivery.reload).to be_sending
    expect(campaign.reload).to be_running
  end

  it 'does not reconcile a test delivery whose own account differs from the native message account' do
    test_delivery = JrcCampaigns::TestDelivery.create!(
      account: create(:account), inbox: inbox, requested_by: admin, status: 'sending', phone_number: contact.phone_number,
      idempotency_key: SecureRandom.uuid, payload_digest: 'd' * 64, external_id: delivery.external_id,
      metadata: { 'message_id' => message.id, 'conversation_id' => message.conversation.display_id }
    )
    message.update!(additional_attributes: {
                      'jrc_campaign_broker' => true, 'campaign_id' => "test:#{test_delivery.id}", 'jrc_campaign_test_delivery_id' => test_delivery.id
                    })
    original = message.attributes.slice('status', 'content_attributes')
    result = described_class.call(message: message, delivery: test_delivery, failure_code: 'JRC_BROKER_DELIVERY_CONTEXT_CHANGED')
    expect(result).to be(false)
    expect(test_delivery.reload.status).to eq('sending')
    expect(message.reload.attributes.slice(*original.keys)).to eq(original)
    expect(campaign.reload).to be_running
  end

  it 'preserves cancellation committed immediately before the failure pause writes its status' do
    canceled = false
    allow(ActiveRecord::Base.connection).to receive(:exec_update).and_wrap_original do |original, sql, *args, **kwargs|
      paused_binding = args.flatten.any? { |value| value.respond_to?(:value_for_database) && value.value_for_database == 'paused' }
      paused = sql.include?("'paused'") || paused_binding
      if !canceled && sql.start_with?('UPDATE "jrc_campaigns"') && paused
        canceled = true
        JrcCampaigns::Campaign.find(campaign.id).cancel!
      end
      original.call(sql, *args, **kwargs)
    end
    stub_request(:post, callback).to_return(status: 403)
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    expect(canceled).to be(true)
    expect(delivery.reload).to be_failed
    expect(campaign.reload).to be_canceled
    expect(execution.reload).to be_canceled
  end

  it 'does not write campaign diagnostics if the campaign marker is removed before its row lock' do
    allow(message).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      Message.find(message.id).update!(additional_attributes: {})
      original.call(*args, &block)
    end
    JrcBroker::WebhookDiagnostic.new(message).callback_started!
    expect(message.reload.content_attributes).not_to have_key('jrc_broker_delivery')
  end

  it 'does not reconcile a message whose campaign marker changes before the delivery lock' do
    Messages::StatusUpdateService.new(message, 'failed', 'JRC_BROKER_DELIVERY_REJECTED').perform
    allow(delivery).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      current = Message.find(message.id)
      current.update!(additional_attributes: current.additional_attributes.except('jrc_campaign_broker'))
      original.call(*args, &block)
    end
    result = described_class.call(message: message, delivery: delivery)
    expect(result).to be(false)
    expect(delivery.reload).to be_sending
    expect(campaign.reload).to be_running
  end

  it 'records only bounded diagnostic fields and never the failure body, URL, credentials or content' do
    warnings = []
    allow(Rails.logger).to receive(:warn) { |line| warnings << line.to_s }
    stub_request(:post, callback).to_return(status: 403, body: 'private-provider-body synthetic-private-key')
    Webhooks::Trigger.execute(callback, payload, :api_inbox_webhook, secret: channel.secret, delivery_id: delivery_id)
    diagnostic = message.reload.content_attributes.fetch('jrc_broker_delivery')
    expect(diagnostic).to include('phase' => 'callback', 'http_status' => 403, 'error_class' => 'SafeFetch::HttpError', 'outcome' => 'rejected')
    serialized = [diagnostic, delivery.reload.metadata['broker_failure'], warnings].to_json
    [callback, channel.secret, 'private-provider-body', 'synthetic-private-key', step.body].each do |private_value|
      expect(serialized).not_to include(private_value)
    end
    expect(warnings.join).to include('callback', 'SafeFetch::HttpError', '403')
  end
end
