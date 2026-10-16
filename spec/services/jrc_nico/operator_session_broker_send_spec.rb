require 'rails_helper'

RSpec.describe JrcNico::OperatorSession do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot: bot) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:organization_id) { SecureRandom.uuid }
  let(:integration_id) { SecureRandom.uuid }
  let(:takeover_id) { SecureRandom.uuid }
  let(:operator) { described_class.new(account: account, user: user) }
  let(:base) { "https://broker.example.test/v1/integrations/chatwoot/control/connections/#{integration_id}/conversations/#{conversation.display_id}" }
  let(:content) { 'Resposta aprovada pelo operador: Olá, posso ajudar.' }
  let(:snapshot) do
    { organizationId: organization_id, integrationId: integration_id, channelId: SecureRandom.uuid,
      conversationId: SecureRandom.uuid, accountId: account.id, inboxId: inbox.id, remoteConversationId: conversation.display_id,
      remoteContactId: conversation.contact_id,
      ownerRevision: 3, attendanceRevision: 9, controlRevision: 4, destinationRevision: 1, credentialRevision: 2, mode: 'BOT' }
  end

  around do |example|
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test',
                      JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('k' * 32), FRONTEND_URL: 'https://central.example.test') { example.run }
  end

  before do
    account.enable_features!('jrc_broker')
    encrypted = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-control')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: organization_id,
                                 destination_revision: 1, encrypted_control_key: encrypted)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: SecureRandom.uuid)
    stub_request(:get, 'https://broker.example.test/v1/integrations/chatwoot/control/context').to_return(status: 200, body: {
      organizationId: organization_id, accountId: account.id, chatwootOrigin: 'https://central.example.test', destinationRevision: 1
    }.to_json)
    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.to_json)
  end

  def prepare_send
    operator.ask(message: 'Envie esta resposta para a conversa selecionada', request_id: SecureRandom.uuid,
                 prepared: { 'tool' => 'send_message', 'arguments' => {
                   'conversation_id' => conversation.display_id, 'content' => content, 'private' => false
                 } })
  end

  def takeover_body(command, state = 'PAUSED')
    snapshot.merge(id: takeover_id, state: state, requestId: command.request_id,
                   fingerprint: command.broker_send_operation.fingerprint, attendanceRevision: 10, controlRevision: 5)
  end

  def stub_pause(command, state = 'PAUSED')
    stub_request(:post, "#{base}/takeovers")
      .with(headers: { 'Idempotency-Key' => command.request_id, 'X-JRC-External-Actor' => user.id.to_s })
      .to_return(status: 200, body: takeover_body(command, state).to_json)
  end

  def stub_completion(command, timeout: false)
    stub = stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete")
    return stub.to_timeout if timeout

    stub.to_return(status: 200, body: takeover_body(command, 'COMPLETED').to_json)
  end

  it 'prepares an explicit takeover preview without changing attendance or sending a message' do
    before_routing = conversation.attributes.slice('status', 'assignee_id', 'assignee_agent_bot_id')
    command = nil
    expect { command = prepare_send }.not_to change(conversation.messages.outgoing, :count)

    expect(command.status).to eq('awaiting_confirmation')
    expect(command.result.dig('broker_send', 'phase')).to eq('PREVIEW')
    expect(command.reply).to include('assumir esta conversa', 'pausar o bot', conversation.contact.name)
    expect(conversation.reload.attributes.slice(*before_routing.keys)).to eq(before_routing)
    expect(a_request(:get, "#{base}/attendance")).to have_been_made.once
    expect(a_request(:post, "#{base}/takeovers")).not_to have_been_made
  end

  it 'creates one public message after confirmed pause and keeps human attendance across duplicate jobs and approvals', :aggregate_failures do
    command = prepare_send
    stub_pause(command)
    stub_completion(command)

    2.times { operator.execute(command.reload) }
    expect(command.reload.status).to eq('executing')
    expect(conversation.messages.outgoing).to be_empty
    2.times { JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id) }

    messages = conversation.messages.outgoing.where(private: false)
    expect(messages.count).to eq(1)
    expect(messages.first.content).to eq(content)
    expect(messages.first.sender).to eq(user)
    expect(messages.first.content_attributes.fetch('jrc_nico_takeover')).to eq(
      'takeoverId' => takeover_id, 'requestId' => command.request_id, 'fingerprint' => command.broker_send_operation.fingerprint
    )
    expect(command.reload.status).to eq('succeeded')
    expect(command.result.dig('broker_send', 'delivery')).to eq(messages.first.status)
    expect(conversation.reload).to be_open
    expect(conversation.assignee_id).to eq(user.id)
    expect(conversation.assignee_agent_bot_id).to be_nil
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  it 'waits for in-flight automation reconciliation without creating a customer message' do
    command = prepare_send
    stub_pause(command, 'DRAINING')
    operator.execute(command)

    expect { JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id) }
      .not_to change(conversation.messages.outgoing, :count)
    expect(command.broker_send_operation.reload.state).to eq('DRAINING')
    expect(command.reload.status).to eq('executing')
  end

  it 'reconciles a lost completion acknowledgement without creating or sending another message' do
    command = prepare_send
    stub_pause(command)
    stub_completion(command, timeout: true)
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    first_id = conversation.messages.outgoing.first.id
    expect(command.broker_send_operation.reload.state).to eq('MESSAGE_CREATED')

    stub_completion(command)
    travel 1.minute do
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    end
    expect(conversation.messages.outgoing.pluck(:id)).to eq([first_id])
    expect(command.reload.status).to eq('succeeded')
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  it 'revalidates operator membership after confirmation and never sends on behalf of a removed user' do
    command = prepare_send
    operator.execute(command)
    account.account_users.find_by!(user: user).destroy!

    expect { JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id) }
      .not_to change(conversation.messages.outgoing, :count)
    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
    expect(a_request(:post, "#{base}/takeovers")).not_to have_been_made
  end

  it 'rejects changed recipients and cross-Account snapshots before confirmation' do
    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.merge(accountId: account.id + 1).to_json)
    expect { prepare_send }.to raise_error(ArgumentError, /vínculo/)

    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.to_json)
    command = prepare_send
    conversation.update!(contact: create(:contact, account: account))
    expect { operator.execute(command) }.to raise_error(ArgumentError, /destinatário/)
    expect(a_request(:post, "#{base}/takeovers")).not_to have_been_made
  end

  it 'does not retry a definite refusal as a temporary pause failure' do
    command = prepare_send
    stub_request(:post, "#{base}/takeovers").to_return(status: 403, body: '{}')
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
    stub_request(:post, "#{base}/takeovers/cancel").to_return(status: 200, body: takeover_body(command, 'CANCELED').to_json)
    travel 2.minutes do
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    end
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'reconciles a lost pause acknowledgement with the same request and sends only after the confirmed retry' do
    command = prepare_send
    stub = stub_request(:post, "#{base}/takeovers").with(headers: { 'Idempotency-Key' => command.request_id })
                                                   .to_timeout.then.to_return(status: 200, body: takeover_body(command).to_json)
    stub_completion(command)
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    expect(conversation.messages.outgoing).to be_empty
    expect(command.broker_send_operation.reload.state).to eq('UNKNOWN')

    travel 1.minute do
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    end
    expect(conversation.messages.outgoing.count).to eq(1)
    expect(command.reload.status).to eq('succeeded')
    expect(stub).to have_been_requested.twice
  end

  it 'does not hold application transaction locks during Broker requests' do
    baseline_depth = ActiveRecord::Base.connection.open_transactions
    command = prepare_send
    stub_request(:post, "#{base}/takeovers").to_return do
      expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline_depth)
      { status: 200, body: takeover_body(command).to_json }
    end
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_return do
      expect(ActiveRecord::Base.connection.open_transactions).to eq(baseline_depth)
      { status: 200, body: takeover_body(command, 'COMPLETED').to_json }
    end
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    expect(command.reload.status).to eq('succeeded')
  end

  it 'rechecks membership after the remote pause and preserves another conversation' do
    other = create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot: bot)
    command = prepare_send
    stub_request(:post, "#{base}/takeovers").to_return do
      account.account_users.find_by!(user: user).destroy!
      { status: 200, body: takeover_body(command).to_json }
    end
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect(conversation.messages.outgoing).to be_empty
    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
    expect(other.reload).to be_pending
    expect(other.assignee_agent_bot_id).to eq(bot.id)
  end

  it 'rejects an expired preview and changes to approved content without creating a pause intent' do
    command = prepare_send
    command.update!(created_at: 16.minutes.ago)
    expect { operator.execute(command) }.to raise_error(ArgumentError, /expirou/)

    command.update!(created_at: Time.current, arguments: command.arguments.merge('content' => 'Changed after preview'))
    expect { operator.execute(command) }.to raise_error(ArgumentError, /destinatário/)
    expect(a_request(:post, "#{base}/takeovers")).not_to have_been_made
  end

  it 'does not create a message when the remote pause receipt belongs to another Account' do
    command = prepare_send
    stub_request(:post, "#{base}/takeovers")
      .to_return(status: 200, body: takeover_body(command).merge(accountId: account.id + 1).to_json)
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect(conversation.messages.outgoing).to be_empty
    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
  end

  it 'uses read-only reconciliation once the remote takeover ID is known' do
    command = prepare_send
    stub_pause(command, 'DRAINING')
    stub_request(:get, "#{base}/takeovers/#{takeover_id}").to_return(status: 200, body: takeover_body(command).to_json)
    stub_completion(command)
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    travel 1.minute do
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    end

    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
    expect(a_request(:get, "#{base}/takeovers/#{takeover_id}")).to have_been_made.once
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it 'uses the same UTF-8 receipt fingerprint as the Broker for Unicode and escaped text' do
    vector = { 'organizationId' => '11111111-2222-4333-8444-555555555555', 'accountId' => 1, 'inboxId' => 2, 'remoteConversationId' => 3 }
    text = "Olá <JRC> 😀\n\"teste\""
    expect(JrcNico::BrokerSendCoordinator.fingerprint(vector, 4, text))
      .to eq('d7cc58a450c97d442385e8621b3dc880248af6bc6bd58a04ad4f8d2ce03fb4e7')
  end

  it 'reports the current observed message status instead of freezing the enqueue receipt' do
    command = prepare_send
    stub_pause(command)
    stub_completion(command)
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    command.broker_send_operation.reload.message.update!(status: 'delivered')

    expect(command.reload.snapshot.dig('result', 'broker_send', 'delivery')).to eq('delivered')
  end

  it 'cancels a pending send irreversibly before releasing the remote intent', :aggregate_failures do
    command = prepare_send
    stub_pause(command, 'DRAINING')
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    operator.cancel(command.reload)

    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
    expect(conversation.messages.outgoing).to be_empty
    stub_request(:post, "#{base}/takeovers/cancel")
      .with(body: { requestId: command.request_id, fingerprint: command.broker_send_operation.fingerprint }.to_json)
      .to_return(status: 200, body: takeover_body(command, 'CANCELED').merge(mode: 'HUMAN').to_json)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect(command.broker_send_operation.reload.state).to eq('CANCELED')
    expect(command.reload.status).to eq('cancelled')
    expect(conversation.reload.attributes.slice('status', 'assignee_id', 'assignee_agent_bot_id'))
      .to eq('status' => 'open', 'assignee_id' => nil, 'assignee_agent_bot_id' => nil)
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'invalidates an active lease when the operator cancels while the remote pause is responding' do
    command = prepare_send
    stub_request(:post, "#{base}/takeovers").to_return do
      operator.cancel(command.reload)
      { status: 200, body: takeover_body(command).to_json }
    end
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'records cancellation by request ID after a lost pause acknowledgement and never starts another pause' do
    command = prepare_send
    stub_request(:post, "#{base}/takeovers").to_timeout
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    expect(command.broker_send_operation.reload.takeover_id).to be_nil
    operator.cancel(command.reload)
    stub_request(:post, "#{base}/takeovers/cancel")
      .to_timeout.then.to_return(status: 200, body: takeover_body(command, 'CANCELED').merge(mode: 'BOT').to_json)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    expect(command.broker_send_operation.reload.state).to eq('CANCELING')
    travel 1.minute do
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    end

    expect(command.broker_send_operation.reload.state).to eq('CANCELED')
    expect(conversation.reload.assignee_agent_bot_id).to eq(bot.id)
    expect(conversation.messages.outgoing).to be_empty
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  it 'never cancels or recreates a message whose creation was already committed' do
    command = prepare_send
    stub_pause(command)
    stub_completion(command, timeout: true)
    operator.execute(command)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)

    expect { operator.cancel(command.reload) }.to raise_error(ArgumentError, /registrada/)
    message = command.broker_send_operation.reload.message
    message.destroy!
    travel 1.minute do
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    end

    expect(command.broker_send_operation.reload.state).to eq('HALTED')
    expect(command.broker_send_operation.last_error).to eq('MESSAGE_RECEIPT_MISSING')
    expect(conversation.messages.outgoing).to be_empty
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
    expect(a_request(:post, "#{base}/takeovers/cancel")).not_to have_been_made
  end

  context 'with agent Inbox permissions' do
    let(:user) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, inbox: inbox, user: user) }

    it 'removes a proposed receipt from history when the conversation leaves the authorized Inbox' do
      command = prepare_send
      conversation.update!(inbox: create(:channel_api, account: account).inbox)

      current = described_class.new(account: account, user: user)
      expect(current.session.messages).to be_empty
      expect(command.reload.status).to eq('cancelled')
    end
  end
end
