require 'rails_helper'
require 'timeout'

RSpec.describe JrcNico::BrokerSendCommitGate do
  self.use_transactional_tests = false

  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator, confirmed_at: Time.current) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, assignee_agent_bot: bot) }
  let(:organization_id) { SecureRandom.uuid }
  let(:integration_id) { SecureRandom.uuid }
  let(:takeover_id) { SecureRandom.uuid }
  let(:operator) { JrcNico::OperatorSession.new(account: account, user: user) }
  let(:content) { 'Resposta explicitamente aprovada' }
  let(:base) { "https://broker.example.test/v1/integrations/chatwoot/control/connections/#{integration_id}/conversations/#{conversation.display_id}" }
  let(:snapshot) do
    { organizationId: organization_id, integrationId: integration_id, channelId: SecureRandom.uuid, conversationId: SecureRandom.uuid,
      accountId: account.id, inboxId: inbox.id, remoteConversationId: conversation.display_id, remoteContactId: conversation.contact_id,
      ownerRevision: 3, attendanceRevision: 9, controlRevision: 4, destinationRevision: 1, credentialRevision: 2, mode: 'BOT' }
  end

  around do |example|
    disposable = %w[jrc_nico_gate_test jrc_nico_broker_candidate_test jrc_jornada_candidate_test jrc_production_stability_test
                    jrc_unificacao_20261021_test]
    database = ENV.fetch('POSTGRES_DATABASE', nil)
    enabled = Rails.env.test? && ENV['JRC_NICO_GATE_CONCURRENCY'] == '1' && disposable.include?(database) &&
              ActiveRecord::Base.connection_db_config.database == database &&
              ActiveRecord::Base.connection.adapter_name == 'PostgreSQL'
    skip 'Opt-in requires an explicitly named disposable NICO test database' unless enabled
    with_modified_env(JRC_BROKER_ENABLED: 'true', JRC_BROKER_ALLOWED_ORIGINS: 'https://broker.example.test',
                      JRC_BROKER_CREDENTIAL_KEY: Base64.strict_encode64('k' * 32), FRONTEND_URL: 'https://central.example.test') do
      clear_committed_fixtures
      example.run
    ensure
      clear_committed_fixtures
      Current.reset
    end
  end

  def clear_committed_fixtures
    connection = ActiveRecord::Base.connection
    raise 'Committed fixtures cannot run inside an outer transaction' if connection.transaction_open?

    connection.clear_query_cache
    tables = connection.tables - %w[schema_migrations ar_internal_metadata installation_configs]
    previous_timeout = connection.select_value('SHOW lock_timeout')
    connection.execute("SET lock_timeout='2s'")
    begin
      # The complete application-table set is explicit. Keep monotonic IDs and
      # avoid resetting hundreds of unrelated sequences for every example.
      connection.execute("TRUNCATE #{tables.map { |name| connection.quote_table_name(name) }.join(', ')}")
    rescue ActiveRecord::LockWaitTimeout
      activity = connection.select_all('SELECT pid,state,wait_event_type FROM pg_stat_activity WHERE datname=current_database()')
      raise "Fixture cleanup was blocked; disposable DB sessions: #{activity.to_a.inspect}"
    ensure
      connection.execute("SET lock_timeout=#{connection.quote(previous_timeout)}")
    end
    connection.clear_query_cache
  end

  before do
    account.enable_features!('jrc_broker')
    encrypted = JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'synthetic-control')
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: organization_id,
                                 destination_revision: 1, encrypted_control_key: encrypted)
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: integration_id, instance_id: SecureRandom.uuid)
    stub_request(:get, 'https://broker.example.test/v1/integrations/chatwoot/control/context')
      .to_return(status: 200, body: { organizationId: organization_id, accountId: account.id,
                                      chatwootOrigin: 'https://central.example.test', destinationRevision: 1 }.to_json)
    stub_request(:get, "#{base}/attendance").to_return(status: 200, body: snapshot.to_json)
  end

  def prepare_send
    operator.ask(message: 'Envie a resposta para esta conversa', request_id: SecureRandom.uuid,
                 prepared: { 'tool' => 'send_message', 'arguments' => {
                   'conversation_id' => conversation.display_id, 'content' => content, 'private' => false
                 } })
  end

  def receipt(command, state = 'PAUSED')
    snapshot.merge(id: takeover_id, requestId: command.request_id, fingerprint: command.broker_send_operation.fingerprint,
                   state: state, attendanceRevision: 10, controlRevision: 5)
  end

  def pause_and_complete(command, pause_state: 'PAUSED')
    stub_request(:post, "#{base}/takeovers").to_return(status: 200, body: receipt(command, pause_state).to_json)
    stub_request(:get, "#{base}/takeovers/#{takeover_id}").to_return(status: 200, body: receipt(command).to_json)
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_return(status: 200, body: receipt(command, 'COMPLETED').to_json)
  end

  def worker(id)
    thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        JrcNico::BrokerSendJob.perform_now(id)
        expect(connection.open_transactions).to eq(0)
        expect(connection.raw_connection.transaction_status).to eq(PG::PQTRANS_IDLE)
      ensure
        connection.disconnect! if connection.raw_connection.transaction_status != PG::PQTRANS_IDLE
      end
    end
    thread.report_on_exception = false
    thread
  end

  def hold_message_until_commit(reached, release)
    allow(Messages::MessageBuilder).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      builder = original.call(*args, **kwargs)
      allow(builder).to receive(:perform).and_wrap_original do |perform, *arguments|
        result = perform.call(*arguments)
        reached << true
        release.pop
        result
      end
      builder
    end
  end

  def wait_for_pg_lock(pid)
    Timeout.timeout(5) do
      loop do
        locked = ActiveRecord::Base.connection.select_value("select wait_event_type='Lock' from pg_stat_activity where pid=#{Integer(pid)}")
        break if locked

        Thread.pass
      end
    end
  end

  def change_broker_destination(field)
    if field == 'binding_instance'
      JrcBrokerInboxBinding.find_by!(inbox_id: inbox.id).update!(instance_id: SecureRandom.uuid)
      return
    end

    values = { 'destination_revision' => 2, 'broker_origin' => 'https://changed-broker.example.test',
               'organization_id' => SecureRandom.uuid,
               'encrypted_control_key' => JrcBroker::Configuration.credential_store.encrypt(account_id: account.id, token: 'rotated-synthetic') }
    JrcBrokerIntegration.find_by!(account_id: account.id).update!(field => values.fetch(field))
  end

  it 'does not create while an authoritative role revocation is uncommitted and does not replay the pause' do
    command = prepare_send
    pause_and_complete(command)
    operator.execute(command)
    thread = nil
    AccountUser.transaction do
      membership = account.account_users.find_by!(user: user)
      membership.update!(role: :agent)
      thread = worker(command.broker_send_operation.id)
      Timeout.timeout(15) { thread.value }
      expect(conversation.messages.outgoing.count).to eq(0)
    end
    travel(1.minute) { JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id) }
    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  ensure
    thread&.kill if thread&.alive?
    thread&.join
  end

  %w[role inbox_grant].each do |grant|
    it "keeps the worker #{grant} stable until its Message transaction commits" do
      if grant == 'inbox_grant'
        account.account_users.find_by!(user: user).update!(role: :agent)
        create(:inbox_member, inbox: inbox, user: user)
      end
      command = prepare_send
      pause_and_complete(command)
      operator.execute(command)
      reached = Queue.new
      release = Queue.new
      update_started = Queue.new
      hold_message_until_commit(reached, release)
      sending = worker(command.broker_send_operation.id)
      Timeout.timeout(15) { reached.pop }
      membership_id = account.account_users.find_by!(user: user).id
      changing = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          update_started << connection.select_value('select pg_backend_pid()').to_i
          if grant == 'role'
            AccountUser.find(membership_id).update!(role: :agent)
          else
            InboxMember.find_by!(inbox: inbox, user: user).destroy!
          end
        end
      end
      changing.report_on_exception = false
      pid = Timeout.timeout(5) { update_started.pop }
      wait_for_pg_lock(pid)
      expect(changing).to be_alive
      release << true
      Timeout.timeout(15) do
        sending.value
        changing.value
      end
      expect(conversation.messages.outgoing.count).to eq(1)
    ensure
      release << true if release && sending&.alive?
      [sending, changing].compact.each do |thread|
        thread.kill if thread.alive?
        thread.join
      end
    end
  end

  it 'refuses a user who became unconfirmed after explicit approval' do
    command = prepare_send
    pause_and_complete(command)
    operator.execute(command)
    user.update!(confirmed_at: nil)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'keeps an authorized offline user eligible' do
    command = prepare_send
    pause_and_complete(command)
    operator.execute(command)
    account.account_users.find_by!(user: user).update!(availability: :offline)
    JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
    expect(conversation.messages.outgoing.count).to eq(1)
  end

  it 'can cancel a draining intent after NICO is disabled without authorizing a new send' do
    command = prepare_send
    pause_and_complete(command, pause_state: 'DRAINING')
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    account.update!(custom_attributes: account.custom_attributes.merge('nico_enabled' => false))
    stub_request(:post, "#{base}/takeovers/cancel").to_return(status: 200, body: receipt(command, 'CANCELED').merge(mode: 'HUMAN').to_json)
    travel 1.minute do
      2.times { JrcNico::BrokerSendJob.perform_now(operation.id) }
    end
    expect(operation.reload.state).to eq('CANCELED')
    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
    expect(conversation.reload.assignee_agent_bot_id).to be_nil
  end

  it 'invalidates the preview when contact inbox routing changes without changing the Contact or Inbox' do
    command = prepare_send
    conversation.contact_inbox.update!(source_id: 'changed-synthetic-recipient')
    expect { operator.execute(command) }.to raise_error(ArgumentError, /destinatário|controle/)
    expect(a_request(:post, "#{base}/takeovers")).not_to have_been_made
  end

  %w[destination_revision encrypted_control_key broker_origin organization_id binding_instance].each do |field|
    it "revalidates #{field} after the remote pause and before Message commit" do
      command = prepare_send
      pause_and_complete(command)
      stub_request(:post, "#{base}/takeovers").to_return do
        change_broker_destination(field)
        { status: 200, body: receipt(command).to_json }
      end
      operator.execute(command)
      JrcNico::BrokerSendJob.perform_now(command.broker_send_operation.id)
      expect(conversation.messages.outgoing.count).to eq(0)
    end
  end

  it 'can clean up a paused intent after membership revocation without authorizing another send' do
    command = prepare_send
    pause_and_complete(command, pause_state: 'DRAINING')
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    cancellation = receipt(command, 'CANCELED').merge(mode: 'HUMAN')
    account.account_users.find_by!(user: user).destroy!
    stub_request(:post, "#{base}/takeovers/cancel").to_return(status: 200, body: cancellation.to_json)
    travel(1.minute) { 2.times { JrcNico::BrokerSendJob.perform_now(operation.id) } }
    expect(operation.reload.state).to eq('CANCELED')
    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  it 'keeps an account owned cancel-only ledger after Command deletion while waiting for a pause' do
    command = prepare_send
    pause_and_complete(command, pause_state: 'DRAINING')
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    fingerprint = operation.reload.fingerprint
    request_id = command.request_id
    command.destroy!
    expect(JrcNico::BrokerSendOperation.exists?(operation.id)).to be(true)
    expect(operation.reload.actor_id).to eq(user.id)
    stub_request(:post, "#{base}/takeovers/cancel").to_return(status: 200, body: snapshot.merge(
      id: takeover_id, requestId: request_id, fingerprint: fingerprint, state: 'CANCELED', mode: 'HUMAN'
    ).to_json)
    travel(1.minute) { 2.times { JrcNico::BrokerSendJob.perform_now(operation.id) } }
    expect(operation.reload.state).to eq('CANCELED')
    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  it 'retains the ledger when the last Account user is deleted and never invents a replacement actor' do
    command = prepare_send
    pause_and_complete(command, pause_state: 'DRAINING')
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    cancellation = receipt(command, 'CANCELED').merge(mode: 'HUMAN')
    actor_id = user.id
    account.account_users.find_by!(user: user).destroy!
    DeleteObjectJob.perform_now(user)
    expect(JrcNico::BrokerSendOperation.exists?(operation.id)).to be(true)
    expect(operation.reload).to have_attributes(user_id: nil, command_id: nil, actor_id: actor_id)
    stub_request(:post, "#{base}/takeovers/cancel").with(headers: { 'X-JRC-External-Actor' => actor_id.to_s })
                                                   .to_return(status: 200, body: cancellation.to_json)
    travel(1.minute) { 2.times { JrcNico::BrokerSendJob.perform_now(operation.id) } }
    expect(operation.reload.state).to eq('CANCELED')
    expect(conversation.messages.outgoing.count).to eq(0)
  end

  it 'preserves the Message creation fact after Message deletion and refuses replay' do
    command = prepare_send
    pause_and_complete(command)
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_timeout
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    created = operation.reload.message_created_at
    expect(created).to be_present
    expect { operation.update!(message_created_at: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    operation.reload
    expect do
      JrcNico::BrokerSendOperation.transaction do
        ActiveRecord::Base.connection.execute(
          "UPDATE jrc_nico_broker_send_operations SET actor_id=#{Integer(user.id) + 1} WHERE id=#{Integer(operation.id)}"
        )
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /immutable/)
    operation.message.destroy!
    travel(1.minute) { JrcNico::BrokerSendJob.perform_now(operation.id) }
    expect(operation.reload).to have_attributes(state: 'HALTED', message_created_at: created, message_id: nil)
    expect(conversation.messages.outgoing.count).to eq(0)
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
    expect(a_request(:post, "#{base}/takeovers/cancel")).not_to have_been_made
  end

  it 'reconciles the same canonical Message after its Command has been deleted' do
    command = prepare_send
    pause_and_complete(command)
    completion = receipt(command, 'COMPLETED')
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_timeout
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    message_id = operation.reload.message_id
    command.destroy!
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_return(status: 200, body: completion.to_json)
    travel(1.minute) { JrcNico::BrokerSendJob.perform_now(operation.id) }
    expect(operation.reload).to have_attributes(state: 'COMPLETED', message_id: message_id, command_id: nil)
    expect(conversation.messages.outgoing.pluck(:id)).to eq([message_id])
    expect(a_request(:post, "#{base}/takeovers")).to have_been_made.once
  end

  it 'retains the irreversible creation fact when User deletion nullifies the canonical sender' do
    command = prepare_send
    pause_and_complete(command)
    stub_request(:post, "#{base}/takeovers/#{takeover_id}/complete").to_timeout
    operator.execute(command)
    operation = command.broker_send_operation
    JrcNico::BrokerSendJob.perform_now(operation.id)
    created = operation.reload.message_created_at
    expect(created).to be_present
    account.account_users.find_by!(user: user).destroy!
    DeleteObjectJob.perform_now(user)
    expect(operation.reload.message_created_at).to eq(created)
    travel(1.minute) { JrcNico::BrokerSendJob.perform_now(operation.id) }
    expect(operation.reload).to have_attributes(state: 'HALTED', message_created_at: created)
    expect(conversation.messages.outgoing.count).to eq(1)
    expect(a_request(:post, "#{base}/takeovers/cancel")).not_to have_been_made
  end
end
