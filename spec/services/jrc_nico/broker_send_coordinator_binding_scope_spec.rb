require 'rails_helper'

RSpec.describe JrcNico::BrokerSendCoordinator do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator, confirmed_at: Time.current) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open, assignee_agent_bot: nil) }
  let(:organization_id) { SecureRandom.uuid }
  let(:integration_id) { SecureRandom.uuid }
  let(:channel_id) { SecureRandom.uuid }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: user) }
  let(:arguments) { { 'conversation_id' => conversation.display_id, 'content' => 'Resposta aprovada', 'private' => false } }
  let(:base) { "https://broker.example.test/v1/integrations/chatwoot/control/connections/#{integration_id}/conversations/#{conversation.display_id}" }
  let(:snapshot) do
    { organizationId: organization_id, integrationId: integration_id, channelId: channel_id, conversationId: SecureRandom.uuid,
      accountId: account.id, inboxId: inbox.id, remoteConversationId: conversation.display_id, remoteContactId: conversation.contact_id,
      ownerRevision: 3, attendanceRevision: 9, controlRevision: 4, destinationRevision: 1, credentialRevision: 2, mode: 'BOT' }
  end

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test',
                      JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('k' * 32), FRONTEND_URL: 'https://central.example.test') { example.run }
  end

  before { account.enable_features!('jrc_broker') }

  def prepare_send(private_note: false)
    operator.ask(message: 'Envie esta resposta para a conversa selecionada', request_id: SecureRandom.uuid,
                 prepared: { 'tool' => 'send_message', 'arguments' => arguments.merge('private' => private_note) })
  end

  def account_control
    encrypted = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-control')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: organization_id,
                                 destination_revision: 1, encrypted_control_key: encrypted)
    stub_request(:get, 'https://broker.example.test/v1/integrations/chatwoot/control/context')
      .to_return(status: 200, body: { organizationId: organization_id, accountId: account.id,
                                      chatwootOrigin: 'https://central.example.test', destinationRevision: 1 }.to_json)
    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.to_json)
  end

  def qr_binding
    account_control
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: SecureRandom.uuid)
  end

  def native_registration(expires_at:, transport:)
    credential_id = SecureRandom.uuid
    JrcFlowNativeRegistration.create!(
      account: account, created_by: user, account_user: account.account_users.find_by!(user: user),
      broker_origin: 'https://broker.example.test', host_origin: 'https://central.example.test', organization_id: organization_id,
      challenge_id: SecureRandom.uuid, credential_id: credential_id, credential_revision: 1,
      destination_revision: 1, account_credential_version: 2, revision: 1,
      state: 'ACTIVE', broker_registration_id: SecureRandom.uuid, broker_registration_revision: 1,
      callback_digest: SecureRandom.hex(32), encrypted_outbound_credential: 'synthetic-encrypted-native-credential',
      tuple: { 'accountId' => account.id, 'credentialId' => credential_id, 'credentialRevision' => 1, 'destinationRevision' => 1,
               'accountCredentialVersion' => 2, 'targets' => [{ 'inboxId' => inbox.id, 'integrationId' => integration_id,
                                                                'channelId' => channel_id, 'transport' => transport, 'provider' => nil }] },
      expires_at: expires_at, credential_expires_at: expires_at
    )
  end

  def native_binding(transport: 'CENTRAL_TRANSPORT', expires_at: 1.hour.from_now)
    native_registration(expires_at: expires_at, transport: transport).bindings.create!(
      account: account, inbox: inbox, integration_id: integration_id, channel_id: channel_id,
      transport: transport, registration_revision: 1
    )
  end

  def stub_pause_and_completion(command)
    takeover_id = SecureRandom.uuid
    receipt = snapshot.merge(id: takeover_id, requestId: command.request_id, fingerprint: command.broker_send_operation.fingerprint)
    stub_request(:post, "#{base}/takeovers").to_return(status: 200, body: receipt.merge(state: 'PAUSED').to_json)
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_return(status: 200, body: receipt.merge(state: 'COMPLETED').to_json)
  end

  it 'does not create from an approved preview after the same Inbox is moved to another API channel' do
    qr_binding
    command = prepare_send
    stub_pause_and_completion(command)
    operator.execute(command)
    inbox.update!(channel: create(:channel_api, account: account))
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:post, "#{base}/takeovers")).not_to have_been_made
  end

  it 'refuses a stale QR binding whose Inbox no longer uses an API channel' do
    qr_binding
    inbox.update!(channel: create(:channel_widget, account: account))

    expect { prepare_send }.to raise_error(ArgumentError, /caixa|canal|vínculo|destinatário/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  %w[BROKER_TRANSPORT CENTRAL_TRANSPORT].each do |transport|
    it "does not fall back to an ordinary public send for native #{transport} without coordinated control" do
      native_binding(transport: transport)

      expect { prepare_send }.to raise_error(ArgumentError, /Flow|coordenad|vínculo/)
      expect(JrcBrokerInboxBinding.where(account: account, inbox: inbox)).to be_empty
      expect(conversation.messages.outgoing.count).to eq(0)
    end
  end

  it 'keeps the native boundary closed when its registration credentials have expired' do
    native_binding(expires_at: 1.minute.ago)

    expect(JrcFlowNativeRegistration.current).to be_empty
    expect { prepare_send }.to raise_error(ArgumentError, /Flow|coordenad|vínculo/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'rejects an ordinary approval prepared before the native binding was installed' do
    command = prepare_send
    native_binding

    expect { operator.execute(command) }.to raise_error(ArgumentError, /Flow|coordenad|vínculo/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'preserves a private note in a native Inbox without claiming a coordinated public send' do
    native_binding
    command = prepare_send(private_note: true)
    operator.execute(command)

    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(conversation.messages.where(private: false).count).to eq(0)
    expect(command.reload.broker_send_operation).to be_nil
  end

  it 'preserves the ordinary explicitly approved public send for an unbound Inbox' do
    command = prepare_send
    operator.execute(command)

    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
    expect(command.reload.broker_send_operation).to be_nil
  end

  it 'requires adoption before previewing a legacy Inbox routed to the configured Broker' do
    account_control
    inbox.channel.update!(webhook_url: "https://broker.example.test/v1/integrations/chatwoot/#{integration_id}/events")

    expect { prepare_send }.to raise_error(ArgumentError, /adoção|adotar/)
    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:get, "#{base}/attendance")).not_to have_been_made
  end

  it 'revalidates a legacy Broker route installed after ordinary approval' do
    command = prepare_send
    account_control
    inbox.channel.update!(webhook_url: "https://broker.example.test/v1/integrations/chatwoot/#{integration_id}/events")

    expect { operator.execute(command) }.to raise_error(ArgumentError, /adoção|adotar/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'allows a private note in a legacy Broker Inbox without taking over or sending publicly' do
    account_control
    inbox.channel.update!(webhook_url: "https://broker.example.test/v1/integrations/chatwoot/#{integration_id}/events")
    command = prepare_send(private_note: true)
    operator.execute(command)

    expect(conversation.messages.where(private: true).count).to eq(1)
    expect(command.reload.broker_send_operation).to be_nil
    expect(a_request(:get, "#{base}/attendance")).not_to have_been_made
  end

  it 'uses coordinated preview and send after the existing administrative adoption verifies the legacy connection' do
    account_control
    inbox.channel.update!(webhook_url: "https://broker.example.test/v1/integrations/chatwoot/#{integration_id}/events")
    stub_request(:get, "https://broker.example.test/v1/integrations/chatwoot/control/connections/#{integration_id}/status")
      .to_return(status: 200, body: { integrationId: integration_id, integrationStatus: 'READY',
                                      inboxId: inbox.id, instanceId: SecureRandom.uuid }.to_json)

    JrcBroker::Context.new(account: account, user: user).adopt!(integration_id)
    command = prepare_send
    expect(command.result.dig('broker_send', 'phase')).to eq('PREVIEW')
    stub_pause_and_completion(command)
    operator.execute(command)
    2.times { JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id) }

    expect(command.reload.broker_send_operation.state).to eq('COMPLETED')
    expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  ['https://broker.example.test.other.test', 'https://unrelated.example.test',
   'http://broker.example.test', 'https://broker.example.test:8443'].each do |origin|
    it "does not grant Broker authority from a different webhook origin #{origin}" do
      account_control
      inbox.channel.update!(webhook_url: "#{origin}/v1/integrations/chatwoot/#{integration_id}/events")
      command = prepare_send
      operator.execute(command)

      expect(command.reload.broker_send_operation).to be_nil
      expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
      expect(a_request(:get, "#{base}/attendance")).not_to have_been_made
    end
  end

  %w[BROKER_TRANSPORT CENTRAL_TRANSPORT].each do |transport|
    it "coordinates native #{transport} through Account control without creating a QR binding" do
      native_binding(transport: transport)
      account_control
      command = prepare_send

      expect(command.result.dig('broker_send', 'phase')).to eq('PREVIEW')
      stub_pause_and_completion(command)
      operator.execute(command)
      2.times { JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id) }

      expect(conversation.messages.outgoing.where(private: false).count).to eq(1)
      expect(command.reload.broker_send_operation.state).to eq('COMPLETED')
      expect(JrcBrokerInboxBinding.where(account: account, inbox: inbox)).to be_empty
      expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
    end
  end

  it 'rejects attendance for another channel than the registered native target' do
    native_binding
    account_control
    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.merge(channelId: SecureRandom.uuid).to_json)

    expect { prepare_send }.to raise_error(ArgumentError, /Flow|coordenad|vínculo/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'rejects attendance whose Account credential revision differs from the native registration' do
    native_binding
    account_control
    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.merge(credentialRevision: 3).to_json)

    expect { prepare_send }.to raise_error(ArgumentError, /Flow|coordenad|vínculo/)
    expect(conversation.messages.outgoing.count).to eq(0)
  end
end
