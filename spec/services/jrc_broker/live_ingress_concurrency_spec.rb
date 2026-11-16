require 'rails_helper'

RSpec.describe JrcBroker::LiveIngress do
  self.use_transactional_tests = false

  around do |example|
    safe = Rails.env.test? && ENV['JRC_LIVE_CONCURRENCY'] == '1' &&
           ActiveRecord::Base.connection_db_config.database == 'jrc_delivery_reliability_test'
    raise 'Explicit disposable LIVE PostgreSQL runner required' unless safe

    with_modified_env(JRC_BROKER_ENABLED: 'true') { example.run }
  end

  it 'waits for in-flight custody before deletion and never removes an unprotected sibling first' do
    account = create(:account)
    account.enable_features!('jrc_broker')
    admin = create(:user, account: account, role: :administrator)
    inbox = create(:channel_api, account: account).inbox
    sibling = create(:conversation, account: account, inbox: inbox)
    conversation = create(:conversation, account: account, inbox: inbox)
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                               destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    binding = JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    input = { 'protocol' => 'jrc-live-ingress/1', 'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id,
              'instance_id' => binding.instance_id, 'destination_revision' => 1, 'broker_message_id' => SecureRandom.uuid,
              'conversation_id' => conversation.display_id, 'message_type' => 'incoming', 'message_origin' => 'LIVE',
              'content' => 'Synthetic deletion race', 'media' => nil }
    input['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(input.sort.to_h))
    ready = Queue.new
    commit = Queue.new
    deletion_pid = Queue.new
    allow(JrcBrokerLiveReceipt).to receive(:create!).and_wrap_original do |method, **attributes|
      result = method.call(**attributes)
      if attributes.fetch(:account).id == account.id
        ready << true
        commit.pop
      end
      result
    end
    writer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        described_class.new(account: account, user: admin, access_token: admin.access_token).receive(inbox.id, input)
      end
    end
    Timeout.timeout(10) { ready.pop }
    deletion = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        deletion_pid << connection.select_value('SELECT pg_backend_pid()')
        DeleteObjectJob.perform_now(inbox)
      rescue StandardError => error
        error.class.name
      end
    end
    pid = Timeout.timeout(10) { deletion_pid.pop }
    Timeout.timeout(10) do
      loop do
        break if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid=#{Integer(pid)}") == 'Lock'

        sleep 0.02
      end
    end
    expect(Conversation.exists?(sibling.id)).to be(true)
    commit << true
    result = Timeout.timeout(10) { writer.value }
    expect(Timeout.timeout(10) { deletion.value }).to eq('JrcBroker::HistoryRetention::Protected')
    expect(JrcBrokerLiveReceipt.find(result.fetch('receipt_id')).message).to be_persisted
    expect(conversation.reload).to be_persisted
    expect(inbox.reload).to be_persisted
  ensure
    commit << true if commit
    [writer, deletion].compact.each { |thread| thread.join(10) }
  end

  it 'serializes simultaneous same-key commits without duplicate normal LIVE effects' do
    account = create(:account)
    account.enable_features!('jrc_broker')
    admin = create(:user, account: account, role: :administrator)
    inbox = create(:channel_api, account: account).inbox
    conversation = create(:conversation, account: account, inbox: inbox)
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                               destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    binding = JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    input = { 'protocol' => 'jrc-live-ingress/1', 'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id,
              'instance_id' => binding.instance_id, 'destination_revision' => 1, 'broker_message_id' => SecureRandom.uuid,
              'conversation_id' => conversation.display_id, 'message_type' => 'outgoing', 'message_origin' => 'LIVE',
              'content' => 'Synthetic simultaneous LIVE', 'media' => nil }
    input['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(input.sort.to_h))
    token = admin.access_token
    gate = Queue.new
    ready = Queue.new
    clear_enqueued_jobs
    workers = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          receiver = described_class.new(account: account, user: admin, access_token: token)
          ready << true
          gate.pop
          receiver.receive(inbox.id, input)
        end
      end
    end
    2.times { ready.pop }
    2.times { gate << true }
    results = workers.map(&:value)
    expect(results.uniq.size).to eq(1)
    expect(account.messages.where(inbox_id: inbox.id).count).to eq(1)
    expect(JrcBrokerLiveReceipt.where(account_id: account.id).count).to eq(1)
    expect(JrcBrokerWebhookObligation.where(account_id: account.id).count).to eq(1)
    created = enqueued_jobs.select { |job| job[:job] == ActionCableBroadcastJob && job[:args][1] == 'message.created' }
    expect(created.size).to eq(1)
    # Synthetic committed fixtures and proof are retained: no test cleanup deletes KEEP objects.
  end

  it 'serializes LIVE and history creation of the same canonical source across two committed PG connections' do
    account = create(:account)
    account.enable_features!('jrc_broker')
    admin = create(:user, account: account, role: :administrator)
    inbox = create(:channel_api, account: account).inbox
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                               destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    binding = JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    scope = { 'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id, 'instance_id' => binding.instance_id,
              'destination_revision' => 1 }
    token = admin.access_token
    receiver = JrcBroker::HistorySyncV2.new(account: account, user: admin, access_token: token)
    history_scope = scope.merge('history_account_identity' => SecureRandom.uuid)
    conversation_id = SecureRandom.uuid
    route = with_modified_env(JRC_HISTORY_SYNC_V2_ENABLED: 'true') do
      receiver.bootstrap(inbox.id, history_scope.merge('broker_conversation_id' => conversation_id, 'broker_contact_id' => SecureRandom.uuid,
                                                       'recipient' => { 'kind' => 'INDIVIDUAL', 'jid' => '123@lid', 'name' => 'Synthetic race' },
                                                       'occurred_at' => 2.days.ago.to_i, 'conversation_id' => nil))
    end
    source = SecureRandom.uuid
    native = scope.merge('protocol' => 'jrc-live-ingress/1', 'broker_message_id' => source, 'conversation_id' => route.fetch(:conversation_id),
                         'message_type' => 'incoming', 'message_origin' => 'LIVE', 'content' => 'Synthetic source race', 'media' => nil)
    native['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(native.sort.to_h))
    historical = history_scope.merge('broker_conversation_id' => conversation_id, 'broker_message_id' => source,
                                     'provider_message_id' => 'SYNTHETIC-RACE', 'direction' => 'incoming', 'participant_jid' => nil,
                                     'occurred_at' => 1.day.ago.to_i, 'status' => 'sent',
                                     'content' => { 'type' => 'TEXT', 'text' => 'Synthetic source race' })
    results = with_modified_env(JRC_HISTORY_SYNC_V2_ENABLED: 'true') do
      concurrent([
                   -> { described_class.new(account: account, user: admin, access_token: token).receive(inbox.id, native) },
                   -> { JrcBroker::HistorySyncV2.new(account: account, user: admin, access_token: token).call(inbox.id, historical) }
                 ])
    end
    expect(results.map { |row| row[:message_id] || row['message_id'] }.uniq.size).to eq(1)
    expect(account.messages.count).to eq(1)
    expect(JrcBrokerLiveReceipt.where(account: account).count).to eq(1)
    expect(JrcBrokerHistoryReceipt.where(account: account, record_kind: 'MESSAGE').count).to eq(1)
  end

  def concurrent(operations)
    ready = Queue.new
    gate = Queue.new
    workers = operations.map do |operation|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          operation.call
        end
      end
    end
    operations.size.times { ready.pop }
    operations.size.times { gate << true }
    workers.map(&:value)
  end

  it 'dispatches a delayed incoming event after COMMIT with its new unread count and server publication proof' do
    inbox = create(:channel_api).inbox
    account = inbox.account
    account.enable_features!('jrc_broker')
    admin = create(:user, account: account, role: :administrator)
    conversation = create(:conversation, account: account, inbox: inbox, agent_last_seen_at: 1.minute.ago)
    integration = JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                              destination_revision: 1, encrypted_control_key: 'synthetic-unused')
    binding = JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    input = { 'protocol' => 'jrc-live-ingress/1', 'organization_id' => integration.organization_id, 'integration_id' => binding.integration_id,
              'instance_id' => binding.instance_id, 'destination_revision' => 1, 'broker_message_id' => SecureRandom.uuid,
              'conversation_id' => conversation.display_id, 'message_type' => 'incoming', 'message_origin' => 'LIVE',
              'content' => 'Synthetic committed source clock', 'media' => nil, 'occurred_at' => 1.day.ago.to_i }
    input['request_hash'] = Digest::SHA256.hexdigest(JSON.generate(input.sort.to_h))
    clear_enqueued_jobs
    result = described_class.new(account: account, user: admin, access_token: admin.access_token).receive(inbox.id, input)
    receipt = JrcBrokerLiveReceipt.find(result.fetch('receipt_id'))
    event = enqueued_jobs.find { |job| job[:job] == ActionCableBroadcastJob && job[:args][1] == 'message.created' }
    expect(receipt.published_at).to be_present
    expect(event.fetch(:args)[2].with_indifferent_access.dig(:conversation, :unread_count)).to eq(1)
    expect(conversation.reload.unread_incoming_messages.size).to eq(1)
    expect(receipt.message.created_at.to_i).to eq(input.fetch('occurred_at'))
  end
end
