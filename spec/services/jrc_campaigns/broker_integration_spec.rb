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
      destinationRevision: 1, identityRevision: 2, ownerRevision: 0, numberSuffix: '0000', ready: true, reason: nil }
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
    stub_request(:get, %r{#{Regexp.escape(prefix)}/connections/#{integration_id}/conversations/\d+/attendance}).to_return(status: 404)
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

    it 'reserves the committed canonical message before its only callback and reuses the persisted intent' do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.find(delivery.metadata.fetch('message_id'))
      intent_id = SecureRandom.uuid
      payload = message.webhook_data.merge(event: 'message_created')
      reservation = stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
        .with(headers: { 'X-JRC-External-Actor' => admin.id.to_s, 'Idempotency-Key' => "campaign:#{delivery.id}" },
              body: hash_including('messageId' => message.id, 'conversationId' => message.conversation.display_id,
                                   'campaignId' => campaign.id.to_s, 'kind' => 'text', 'text' => step.body,
                                   'destinationRevision' => 1, 'identityRevision' => 2, 'ownerRevision' => 0))
        .to_return(status: 201, headers: { 'Content-Type' => 'application/json' }, body: {
          protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', expiresAt: 5.minutes.from_now.iso8601, replayed: false
        }.to_json)
      expect(SafeFetch).to receive(:fetch).once do |url, **options|
        expect(url).to eq(inbox.channel.webhook_url)
        expect(JSON.parse(options.fetch(:body)).fetch('additional_attributes').fetch('jrc_campaign_intent_id')).to eq(intent_id)
        timestamp = options.fetch(:headers).fetch('X-Chatwoot-Timestamp')
        expected = OpenSSL::HMAC.hexdigest('SHA256', inbox.channel.secret, "#{timestamp}.#{options.fetch(:body)}")
        expect(options.fetch(:headers).fetch('X-Chatwoot-Signature')).to eq("sha256=#{expected}")
      end
      Webhooks::Trigger.execute(inbox.channel.webhook_url, payload, :api_inbox_webhook, secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
      JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(payload)
      expect(reservation).to have_been_requested.once
      expect(message.reload.additional_attributes['jrc_campaign_intent_id']).to eq(intent_id)
      expect(payload[:additional_attributes]['jrc_campaign_intent_id']).to eq(intent_id)
      expect(account.messages.count).to eq(1)
      expect(delivery.reload.sent_at).to be_nil
    end

    ['jrc-00000000-0000-4000-8000-000000000123', '243589774893072@lid'].each do |source_id|
      it "preserves an existing opaque contact-inbox identity #{source_id} when creating the selected sender message" do
        link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: source_id)

        2.times { service.perform }

        expect(recipient.deliveries.sole).to have_attributes(status: 'sending', sent_at: nil)
        message = account.messages.sole
        expect(message.inbox_id).to eq(inbox.id)
        expect(message.conversation.contact_id).to eq(contact.id)
        expect(message.conversation.contact_inbox_id).to eq(link.id)
        expect(link.reload.source_id).to eq(source_id)
        expect(contact.contact_inboxes.where(inbox: inbox).count).to eq(1)
      end

      it "reserves a canonical campaign message whose current source identity is #{source_id}" do
        service.perform
        delivery = recipient.deliveries.sole
        message = account.messages.find(delivery.metadata.fetch('message_id'))
        link = message.conversation.contact_inbox
        link.update!(source_id: source_id)
        intent_id = SecureRandom.uuid
        reservation = stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
        reservation.with(body: hash_including('conversationId' => message.conversation.display_id, 'messageId' => message.id,
                                             'kind' => 'text', 'text' => 'Synthetic message'))
        reservation.to_return(status: 201, headers: { 'Content-Type' => 'application/json' }, body: {
          protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', expiresAt: 5.minutes.from_now.iso8601, replayed: false
        }.to_json)

        JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data)

        expect(message.reload.additional_attributes['jrc_campaign_intent_id']).to eq(intent_id)
        expect(reservation).to have_been_requested.once
        expect(link.reload.source_id).to eq(source_id)
        expect(account.messages.count).to eq(1)
      end
    end

    it 'rejects a selected campaign contact whose canonical phone changed before message creation' do
      row = recipient
      contact.update!(phone_number: '+5511888888000')

      service.perform

      expect(row.deliveries.sole).to be_failed
      expect(account.messages.count).to eq(0)
      expect(account.contacts.where(phone_number: '+5511999999000')).to be_empty
    end

    it 'rejects a selected contact from another Account before creating a message' do
      foreign = create(:contact, account: create(:account), phone_number: '+5511999999000')
      recipient.update!(contact: foreign)

      service.perform

      expect(recipient.deliveries.sole).to be_failed
      expect(account.messages.count).to eq(0)
      expect(foreign.contact_inboxes).to be_empty
    end

    it 'uses the exact existing conversation link when the same contact has three identities in the selected inbox' do
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: '00000000-0000-4000-8000-000000000122')
      older_link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000123')
      current_link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '00000000-0000-4000-8000-000000000124')
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: older_link, created_at: 2.minutes.ago)
      current = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: current_link, created_at: 1.minute.ago)

      2.times { service.perform }

      message = account.messages.sole
      expect(recipient.deliveries.sole).to have_attributes(status: 'sending', sent_at: nil)
      expect(message.conversation_id).to eq(current.id)
      expect(message.conversation.contact_inbox_id).to eq(current_link.id)
      expect(contact.contact_inboxes.where(inbox: inbox).pluck(:source_id)).to contain_exactly(
        '00000000-0000-4000-8000-000000000122', 'jrc-00000000-0000-4000-8000-000000000123', '00000000-0000-4000-8000-000000000124'
      )
      expect(contact.conversations.where(inbox: inbox).count).to eq(2)
    end

    it 'preserves the conversation already assigned to the recipient instead of switching to a newer identity' do
      selected_link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '243589774893072@lid')
      selected = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: selected_link, created_at: 2.minutes.ago)
      newer_link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000123')
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: newer_link, created_at: 1.minute.ago)
      recipient.update!(conversation: selected)
      stub_request(:get, "#{prefix}/connections/#{integration_id}/conversations/#{selected.display_id}/attendance").to_return(
        headers: { 'Content-Type' => 'application/json' }, body: {
          organizationId: JrcBrokerIntegration.find_by!(account: account).organization_id, integrationId: integration_id,
          channelId: SecureRandom.uuid, conversationId: SecureRandom.uuid, accountId: account.id, inboxId: inbox.id,
          remoteContactId: contact.id, remoteConversationId: selected.display_id, destinationRevision: 1,
          credentialRevision: 1, ownerRevision: 0, attendanceRevision: 1, controlRevision: 1, mode: 'HUMAN'
        }.to_json
      )

      service.perform

      expect(recipient.deliveries.sole).to have_attributes(status: 'sending', sent_at: nil)
      expect(account.messages.sole.conversation_id).to eq(selected.id)
      expect(contact.contact_inboxes.where(inbox: inbox).count).to eq(2)
    end

    it 'rejects multiple identities without an existing canonical conversation rather than choosing the first' do
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5511999999000')
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000123')

      service.perform

      expect(recipient.deliveries.sole).to be_failed
      expect(account.messages.count).to eq(0)
      expect(contact.contact_inboxes.where(inbox: inbox).count).to eq(2)
    end

    it 'rejects a recipient conversation belonging to another selected inbox' do
      other_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
      other_link = create(:contact_inbox, contact: contact, inbox: other_inbox)
      conversation = create(:conversation, account: account, inbox: other_inbox, contact: contact, contact_inbox: other_link)
      recipient.update!(conversation: conversation)

      service.perform

      expect(recipient.deliveries.sole).to be_failed
      expect(account.messages.count).to eq(0)
      expect(contact.contact_inboxes.where(inbox: inbox)).to be_empty
    end

    it 'rejects an existing conversation whose contact-inbox link points to another contact' do
      other = create(:contact, account: account)
      mismatched_link = create(:contact_inbox, contact: other, inbox: inbox)
      create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: mismatched_link)

      service.perform

      expect(recipient.deliveries.sole).to be_failed
      expect(account.messages.count).to eq(0)
      expect(mismatched_link.reload.contact_id).to eq(other.id)
    end

    it 'returns only the exact conversation binding in the authenticated canonical GET' do
      link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '243589774893072@lid')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link)
      create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000123')

      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('contact_inbox')).to eq(
        'id' => link.id, 'contact_id' => contact.id, 'inbox_id' => inbox.id, 'source_id' => '243589774893072@lid'
      )
      expect(response.body).not_to include(link.pubsub_token)
    end

    it 'does not expose the canonical binding to an unauthenticated request or a different Account' do
      link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '243589774893072@lid')
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link)
      path = "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}"

      get path
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key('contact_inbox')

      other_admin = create(:user, account: create(:account), role: :administrator)
      get path, headers: other_admin.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).not_to have_key('contact_inbox')
    end

    it 'keeps the authenticated GET available for a legacy conversation without a contact-inbox link' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      conversation.update_column(:contact_inbox_id, nil) # rubocop:disable Rails/SkipsModelValidations

      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('contact_inbox' => nil)
    end

    it 'reports a persisted pause with approval unavailable instead of failing its response when Broker transport is down' do
      stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(status: 503)

      post "/api/v1/accounts/#{account.id}/jrc_campaigns/campaigns/#{campaign.id}/pause", headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('status' => 'paused', 'approval_valid' => false)
      expect(campaign.reload).to be_paused
      expect(account.messages.count).to eq(0)
      expect { campaign.ensure_approved! }.to raise_error(JrcBroker::Client::Error)
    end

    it 'commits a manual recipient correlation together with its canonical message before dispatching the callback' do
      recipient.update!(contact: nil)
      delivery = recipient.deliveries.create!(step: step, inbox: inbox, status: 'sending')

      message = JrcCampaigns::BrokerMessageSender.call(
        delivery: delivery, user: admin, phone_number: recipient.phone_number, step: { 'kind' => 'text', 'body' => 'Synthetic message' },
        attributes: { 'campaign_id' => campaign.id.to_s, 'jrc_campaign_broker_delivery_id' => delivery.id }
      )

      expect(recipient.reload.contact_id).to eq(message.conversation.contact_id)
      expect(recipient.conversation_id).to eq(message.conversation_id)
      expect(delivery.reload.metadata).to include('message_id' => message.id, 'conversation_id' => message.conversation.display_id)
      expect(account.messages.count).to eq(1)
    end

    it 'rolls back the manual recipient correlation when the message cannot be saved' do
      recipient.update!(contact: nil)
      delivery = recipient.deliveries.create!(step: step, inbox: inbox, status: 'sending')

      expect do
        JrcCampaigns::BrokerMessageSender.call(
          delivery: delivery, user: admin, phone_number: recipient.phone_number,
          step: { 'kind' => 'image', 'body' => 'Synthetic caption', 'media_asset_id' => -1 }, attributes: { 'campaign_id' => campaign.id.to_s }
        )
      end.to raise_error(ActiveRecord::RecordNotFound)

      expect(recipient.reload).to have_attributes(contact_id: nil, conversation_id: nil)
      expect(delivery.reload.metadata).not_to have_key('message_id')
      expect(account.messages.count).to eq(0)
      expect(contact.contact_inboxes.where(inbox: inbox)).to be_empty
      expect(contact.conversations.where(inbox: inbox)).to be_empty
    end

    context 'when the canonical recipient changes before the callback' do
      before do
        stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
          .to_return(status: 201, headers: { 'Content-Type' => 'application/json' }, body: {
            protocol: 'chatwoot-campaigns/v1', intentId: SecureRandom.uuid, state: 'RESERVED', expiresAt: 5.minutes.from_now.iso8601, replayed: false
          }.to_json)
      end

      it 'rejects a changed canonical contact phone before reserving the callback intent' do
        service.perform
        message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
        contact.update!(phone_number: '+5511888888000')

        expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
          .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
        expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
      end

      it 'rejects a contact moved to another Account before reserving the callback intent' do
        service.perform
        message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
        contact.update_column(:account_id, create(:account).id) # rubocop:disable Rails/SkipsModelValidations

        expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
          .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
        expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
      end

      it 'rejects a recipient reassigned to a different contact before reserving the callback intent' do
        service.perform
        message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
        recipient.update!(contact: create(:contact, account: account, phone_number: '+5511888888000'))

        expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
          .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
        expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
      end

      it 'rejects a contact-inbox link reassigned to another contact before reserving the callback intent' do
        service.perform
        message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
        link = message.conversation.contact_inbox
        link.update_column(:contact_id, create(:contact, account: account).id) # rubocop:disable Rails/SkipsModelValidations

        expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
          .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
        expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
      end

      it 'rejects a contact-inbox link reassigned to another inbox before reserving the callback intent' do
        service.perform
        message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
        link = message.conversation.contact_inbox
        link.update_column(:inbox_id, create(:inbox, account: account).id) # rubocop:disable Rails/SkipsModelValidations

        expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
          .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
        expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
      end
    end

    it 'does not authorize a campaign marker without the matching server delivery correlation' do
      service.perform
      delivery = recipient.deliveries.sole
      message = account.messages.find(delivery.metadata.fetch('message_id'))
      delivery.update!(metadata: delivery.metadata.merge('message_id' => message.id + 1))
      expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
        .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
      expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
    end

    it 'honors a withdrawal recorded between local message commit and the callback' do
      service.perform
      message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
      JrcCampaigns::Consent.where(account: account).update_all(revoked_at: Time.current)
      expect { JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data) }
        .to raise_error(JrcBroker::WebhookDelivery::ContextChanged)
      expect(WebMock).not_to have_requested(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
    end

    it 'suppresses the callback if the binding was removed after the message committed' do
      service.perform
      message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
      JrcBrokerInboxBinding.where(account: account, inbox: inbox).delete_all
      expect(SafeFetch).not_to receive(:fetch)
      Webhooks::Trigger.execute(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                               secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
      expect(message.reload).to be_failed
    end

    it 'suppresses a queued campaign payload if its canonical campaign marker was removed' do
      service.perform
      message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
      payload = message.webhook_data.merge(event: 'message_created')
      message.update_columns(additional_attributes: {})
      expect(SafeFetch).not_to receive(:fetch)
      Webhooks::Trigger.execute(inbox.channel.webhook_url, payload, :api_inbox_webhook,
                               secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
      expect(message.reload).to be_failed
    end

    it 'retries only the reservation after timeout and never posts an unsigned campaign intent' do
      service.perform
      message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
      stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_timeout
      expect(SafeFetch).not_to receive(:fetch)
      expect do
        Webhooks::Trigger.execute(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                                 secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
      end.to raise_error(JrcBroker::WebhookDelivery::Unavailable)
      expect(message.reload.additional_attributes).not_to have_key('jrc_campaign_intent_id')
      expect(account.messages.count).to eq(1)
    end

    it 'fails a rejected reservation without posting the campaign callback' do
      service.perform
      message = account.messages.find(recipient.deliveries.sole.metadata.fetch('message_id'))
      stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents").to_return(status: 409)
      expect(SafeFetch).not_to receive(:fetch)
      Webhooks::Trigger.execute(inbox.channel.webhook_url, message.webhook_data.merge(event: 'message_created'), :api_inbox_webhook,
                               secret: inbox.channel.secret, delivery_id: SecureRandom.uuid)
      expect(message.reload).to be_failed
      expect(account.messages.count).to eq(1)
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
      expect(message.additional_attributes).to include('campaign_id' => campaign.id.to_s, 'jrc_campaign_broker' => true)
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

    context 'with an image campaign' do
      let(:step) do
        image = JrcCampaigns::MediaAsset.create!(account: account, created_by: admin, kind: 'image',
                                                file: fixture_file_upload(Rails.root.join('spec/assets/sample.png'), 'image/png'))
        campaign.steps.create!(kind: 'image', body: 'Synthetic image caption', position: 0, media_asset_id: image.id,
                                media_url: 'https://storage.example.test/not-requested')
      end

      it 'keeps the caption and private account-owned image on the selected inbox and reserves one image intent' do
        link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000123')
        intent_id = SecureRandom.uuid
        reservation = stub_request(:post, "#{prefix}/connections/#{integration_id}/campaign-intents")
        reservation.with(body: hash_including('kind' => 'image', 'text' => 'Synthetic image caption'))
        reservation.to_return(status: 201, headers: { 'Content-Type' => 'application/json' }, body: {
          protocol: 'chatwoot-campaigns/v1', intentId: intent_id, state: 'RESERVED', expiresAt: 5.minutes.from_now.iso8601, replayed: false
        }.to_json)

        2.times { service.perform }
        message = account.messages.sole
        image = account.jrc_campaign_media_assets.find(step.media_asset_id)
        JrcBroker::WebhookDelivery.new(message).prepare_campaign_intent!(message.webhook_data)

        expect(message.reload).to have_attributes(content: 'Synthetic image caption', inbox_id: inbox.id,
                                                  additional_attributes: hash_including('jrc_campaign_intent_id' => intent_id))
        expect(message.conversation.contact_inbox_id).to eq(link.id)
        expect(message.attachments.sole).to have_attributes(file_type: 'image', account_id: account.id)
        expect(message.attachments.sole.file.blob).to eq(image.file.blob)
        expect(reservation).to have_been_requested.once
        expect(a_request(:get, 'https://storage.example.test/not-requested')).not_to have_been_made
        expect(recipient.deliveries.sole.sent_at).to be_nil
      end
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
    expect { JrcCampaigns::TestMessageService.new(**options.merge(idempotency_key: SecureRandom.uuid)).perform }
      .to raise_error(ArgumentError, /pendente/)
    expect(account.messages.count).to eq(1)
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
