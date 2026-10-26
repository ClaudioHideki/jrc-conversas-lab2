require 'rails_helper'

RSpec.describe 'Broker campaign canonical conversation selection', type: :request do
  subject(:resolution) do
    JrcCampaigns::BrokerConversationResolver.new(connector: connector, user: admin, phone_number: contact.phone_number,
                                                 contact: contact, conversation: explicit_conversation).call
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:origin) { 'https://broker.example.test' }
  let(:integration_id) { SecureRandom.uuid }
  let(:instance_id) { SecureRandom.uuid }
  let(:inbox) do
    create(:inbox, account: account,
                   channel: create(:channel_api, account: account,
                                                 webhook_url: "#{origin}/v1/integrations/chatwoot/#{integration_id}/events"))
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5511999999000') }
  let(:integration) do
    key = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-scoped-key')
    JrcBrokerIntegration.create!(account: account, broker_origin: origin, organization_id: SecureRandom.uuid,
                                 destination_revision: 1, encrypted_control_key: key)
  end
  let!(:bound) do
    link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'jrc-00000000-0000-4000-8000-000000000123')
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link, created_at: 2.minutes.ago)
  end
  let!(:recent) do
    link = create(:contact_inbox, contact: contact, inbox: inbox, source_id: '00000000-0000-4000-8000-000000000124')
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: link, created_at: 1.minute.ago)
  end
  let(:connector) { JrcCampaigns::BrokerConnector.for(inbox) }
  let(:explicit_conversation) { nil }
  let(:snapshot) do
    { 'organizationId' => integration.organization_id, 'integrationId' => integration_id,
      'channelId' => SecureRandom.uuid, 'conversationId' => SecureRandom.uuid,
      'accountId' => account.id, 'inboxId' => inbox.id, 'remoteContactId' => contact.id, 'remoteConversationId' => bound.display_id,
      'destinationRevision' => 1, 'credentialRevision' => 1, 'ownerRevision' => 0, 'attendanceRevision' => 1,
      'controlRevision' => 1, 'mode' => 'HUMAN' }
  end

  around do |example|
    with_modified_env('JRC_BROKER_ENABLED' => 'true', 'JRC_BROKER_ALLOWED_ORIGINS' => origin,
                      'FRONTEND_URL' => 'https://central.example.test',
                      'JRC_BROKER_CREDENTIAL_KEY' => Base64.strict_encode64('s' * 32)) { example.run }
  end

  before do
    account.enable_features!('jrc_broker', 'jrc_campaigns')
    integration
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: instance_id)
    prefix = "#{origin}/v1/integrations/chatwoot/control"
    stub_request(:get, "#{prefix}/context").to_return(headers: { 'Content-Type' => 'application/json' }, body: {
      organizationId: integration.organization_id, accountId: account.id, destinationRevision: 1,
      chatwootOrigin: 'https://central.example.test'
    }.to_json)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/status").to_return(body: '{}')
    stub_request(:get, "#{prefix}/connections/#{integration_id}/campaign-transport").to_return(
      headers: { 'Content-Type' => 'application/json' }, body: {
        protocol: 'chatwoot-campaigns/v1', integrationId: integration_id, instanceId: instance_id, inboxId: inbox.id,
        destinationRevision: 1, identityRevision: 2, ownerRevision: 0, numberSuffix: '0000', ready: true, reason: nil
      }.to_json
    )
    stub_request(:get, %r{#{Regexp.escape(prefix)}/connections/#{integration_id}/conversations/\d+/attendance}).to_return(status: 404)
    stub_request(:get, "#{prefix}/connections/#{integration_id}/conversations/#{bound.display_id}/attendance")
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: snapshot.to_json)
  end

  it 'creates the campaign message on the sole Broker-bound conversation instead of a more recent unmapped conversation' do
    campaign = JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Synthetic canonical routing',
                                              sending_window: { days: [0, 1, 2, 3, 4, 5, 6], start: '00:00', end: '23:59', timezone: 'UTC' })
    step = campaign.steps.create!(kind: 'text', body: 'Synthetic message', position: 0)
    campaign.request_review!
    campaign.approve!(admin, campaign.review_digest)
    campaign.update!(status: 'running')
    execution = campaign.executions.create!(run_number: 1, status: 'running')
    recipient = execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact,
                                             phone_number: contact.phone_number, destination: contact.phone_number)

    2.times { JrcCampaigns::DispatchStepService.new(recipient: recipient, step: step).perform }

    expect(recipient.deliveries.sole).to have_attributes(status: 'sending', sent_at: nil)
    expect(account.messages.sole.conversation_id).to eq(bound.id)
    expect(recipient.reload.conversation_id).to eq(bound.id)
    expect(contact.contact_inboxes.where(inbox: inbox).count).to eq(2)
    expect(contact.conversations.where(inbox: inbox).count).to eq(2)
  end

  it 'returns exactly one proven existing conversation without changing history or making a takeover request' do
    expect(resolution.id).to eq(bound.id)
    expect(contact.conversations.where(inbox: inbox).count).to eq(2)
    expect(WebMock).not_to have_requested(:post, /takeovers/)
  end

  it 'uses the same read-only binding for an individual test and replays it without another lookup or message' do
    values = { connector: connector, user: admin, phone_number: contact.phone_number,
               step: { 'kind' => 'text', 'body' => 'Synthetic individual test' }, idempotency_key: SecureRandom.uuid, operator_confirmed: true }

    first = JrcCampaigns::BrokerTestService.new(**values).perform
    replay = JrcCampaigns::BrokerTestService.new(**values).perform

    expect(replay).to eq(first)
    expect(account.messages.sole.conversation_id).to eq(bound.id)
    expect(WebMock).to have_requested(:get, %r{/conversations/#{bound.display_id}/attendance}).once
    expect(contact.conversations.where(inbox: inbox).count).to eq(2)
  end

  context 'with an explicit recipient conversation' do
    let(:explicit_conversation) { recent }

    it 'refuses an unproven explicit conversation instead of silently rerouting to the other bound conversation' do
      expect { resolution }.to raise_error(ArgumentError, /conversa/i)
      expect(WebMock).not_to have_requested(:get, %r{/conversations/#{bound.display_id}/attendance})
    end
  end

  it 'permits only the existing fresh-selection fallback when no candidate has a positive map proof' do
    stub_request(:get, %r{/conversations/#{bound.display_id}/attendance}).to_return(status: 404)

    expect(resolution).to be_nil
    expect(account.messages).to be_empty
  end

  it 'rejects two positive bindings instead of choosing by order or prefix' do
    stub_request(:get, %r{/conversations/#{recent.display_id}/attendance})
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: snapshot.merge('remoteConversationId' => recent.display_id).to_json)

    expect { resolution }.to raise_error(ArgumentError, /mais de uma/i)
    expect(account.messages).to be_empty
  end

  [403, 409, 503].each do |status|
    it "does not interpret HTTP #{status} as an absent mapping" do
      stub_request(:get, %r{/conversations/#{recent.display_id}/attendance}).to_return(status: status)

      expected_status = status == 503 ? 502 : status
      expect { resolution }.to raise_error(JrcBroker::Client::Error) { |error| expect(error.status).to eq(expected_status) }
      expect(account.messages).to be_empty
    end
  end

  %w[organizationId integrationId accountId inboxId remoteContactId remoteConversationId destinationRevision].each do |field|
    it "rejects a positive snapshot with a different #{field}" do
      value = %w[organizationId integrationId].include?(field) ? SecureRandom.uuid : 0
      stub_request(:get, %r{/conversations/#{bound.display_id}/attendance})
        .to_return(headers: { 'Content-Type' => 'application/json' }, body: snapshot.merge(field => value).to_json)

      expect { resolution }.to raise_error(JrcBroker::Client::Error)
      expect(account.messages).to be_empty
    end
  end

  it 'rejects malformed revision and physical conversation fields' do
    stub_request(:get, %r{/conversations/#{bound.display_id}/attendance})
      .to_return(headers: { 'Content-Type' => 'application/json' }, body: snapshot.merge('conversationId' => 'invalid',
                                                                                         'ownerRevision' => '1').to_json)

    expect { resolution }.to raise_error(JrcBroker::Client::Error)
  end

  it 'bounds the candidate query and does not hide a possible map beyond the limit' do
    stub_const('JrcCampaigns::BrokerConversationResolver::MAX_CANDIDATES', 1)

    expect { resolution }.to raise_error(ArgumentError, /histórico/i)
    expect(WebMock).not_to have_requested(:get, /attendance/)
  end

  it 'rechecks native administration before returning a positive lookup' do
    stub_request(:get, %r{/conversations/#{bound.display_id}/attendance}).to_return do
      account.account_users.find_by!(user: admin).update!(role: :agent)
      { headers: { 'Content-Type' => 'application/json' }, body: snapshot.to_json }
    end

    expect { resolution }.to raise_error(JrcBroker::Client::Error) { |error| expect(error.status).to eq(403) }
    expect(account.messages).to be_empty
  end

  it 'rejects a non-administrator before any remote lookup' do
    account.account_users.find_by!(user: admin).update!(role: :agent)

    expect { resolution }.to raise_error(JrcBroker::Client::Error) { |error| expect(error.status).to eq(403) }
    expect(WebMock).not_to have_requested(:get, %r{attendance|/context})
  end

  it 'rejects a locally changed destination revision after the lookup' do
    stub_request(:get, %r{/conversations/#{bound.display_id}/attendance}).to_return do
      integration.update!(destination_revision: 2)
      { headers: { 'Content-Type' => 'application/json' }, body: snapshot.to_json }
    end

    expect { resolution }.to raise_error(JrcBroker::Client::Error) { |error| expect(error.status).to eq(409) }
    expect(account.messages).to be_empty
  end

  it 'rejects an opaque source identity changed during the read without rewriting it' do
    changed_source = '243589774893072@lid'
    stub_request(:get, %r{/conversations/#{bound.display_id}/attendance}).to_return do
      bound.contact_inbox.update!(source_id: changed_source)
      { headers: { 'Content-Type' => 'application/json' }, body: snapshot.to_json }
    end

    expect { resolution }.to raise_error(ArgumentError, /contato/i)
    expect(bound.contact_inbox.reload.source_id).to eq(changed_source)
    expect(account.messages).to be_empty
  end

  it 'rejects local identity changed during the read without replacing the contact or its link' do
    original_source = bound.contact_inbox.source_id
    stub_request(:get, %r{/conversations/#{bound.display_id}/attendance}).to_return do
      contact.update!(phone_number: '+5511888888000')
      { headers: { 'Content-Type' => 'application/json' }, body: snapshot.to_json }
    end

    expect { resolution }.to raise_error(ArgumentError, /contato/i)
    expect(bound.contact_inbox.reload.source_id).to eq(original_source)
    expect(account.messages).to be_empty
  end

  it 'refreshes a preloaded recipient contact at the final message transaction after resolving a conversation' do
    preferred = resolution
    delivery = synthetic_delivery
    delivery.recipient.contact
    Contact.find(contact.id).update!(phone_number: '+5511888888000')

    expect do
      JrcCampaigns::BrokerMessageSender.call(delivery: delivery, user: admin, phone_number: '+5511999999000', conversation: preferred,
                                             step: { 'kind' => 'text', 'body' => 'Synthetic message' }, attributes: {})
    end.to raise_error(ArgumentError, /contato/i)

    expect(account.messages).to be_empty
    expect(delivery.reload.metadata).not_to have_key('message_id')
  end

  it 'refreshes a preloaded recipient pin and refuses a different conversation before creating the message' do
    preferred = resolution
    delivery = synthetic_delivery
    recipient = delivery.recipient
    recipient.conversation
    recipient.class.find(recipient.id).update!(conversation: recent)

    expect do
      JrcCampaigns::BrokerMessageSender.call(delivery: delivery, user: admin, phone_number: contact.phone_number, conversation: preferred,
                                             step: { 'kind' => 'text', 'body' => 'Synthetic message' }, attributes: {})
    end.to raise_error(ArgumentError, /conversa/i)

    expect(account.messages).to be_empty
    expect(delivery.reload.metadata).not_to have_key('message_id')
  end

  def synthetic_delivery
    campaign = JrcCampaigns::Campaign.create!(account: account, inbox: inbox, created_by: admin, name: 'Synthetic transaction fence')
    step = campaign.steps.create!(kind: 'text', body: 'Synthetic message', position: 0)
    execution = campaign.executions.create!(run_number: 1, status: 'running')
    recipient = execution.recipients.create!(campaign: campaign, inbox: inbox, contact: contact, conversation: bound,
                                             phone_number: contact.phone_number, destination: contact.phone_number)
    recipient.deliveries.create!(step: step, inbox: inbox, status: 'sending')
  end
end
