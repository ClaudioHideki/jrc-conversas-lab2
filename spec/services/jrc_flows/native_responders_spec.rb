require 'rails_helper'

RSpec.describe JrcFlows::NativeResponders, :sd_concurrency, type: :request do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:channel_api, account: account).inbox.tap { |value| value.update!(greeting_enabled: false, enable_auto_assignment: false) }
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending, assignee: nil) }

  around { |example| with_modified_env(FRONTEND_URL: 'https://host.example.test', JRC_FLOWS_ENABLED: 'true', JRC_FLOWS_EXTERNAL_BETA: 'true') { example.run } }

  before do
    # ActionService normally reports and swallows an action error. Let the
    # regression expose its original cause instead of only a missing Message.
    allow(ChatwootExceptionTracker).to receive(:new) { |error, **| raise error }
  end

  def fence(target = inbox)
    scope = JrcFlowOwnershipScope.find_or_create_by!(scope_key: JrcFlows::OwnershipGuard.key('https://host.example.test', account.id,
                                                                                             target.id)) do |value|
      value.host_origin = 'https://host.example.test'
      value.account_id = account.id
      value.inbox_id = target.id
    end
    scope.update!(state: 'FENCED')
    scope
  end

  def rule(actions)
    account.automation_rules.create!(
      name: "Native guard #{SecureRandom.uuid}", event_name: 'message_created', active: false,
      conditions: [{ attribute_key: 'inbox_id', filter_operator: 'equal_to', values: [inbox.id], query_operator: nil }], actions: actions
    )
  end

  def native_message
    value = rule([{ action_name: 'send_message', action_params: ['Guarded native response'] }])
    AutomationRules::ActionService.new(value, account, conversation).perform
    conversation.messages.find_by!(content: 'Guarded native response')
  end

  def canonical_bot
    account.enable_features!('jrc_flows')
    create(:inbox_member, inbox: inbox, user: admin)
    bot = create(:agent_bot, account: account, outgoing_url: 'https://broker.example.test/events')
    AgentBotInbox.create!(account: account, inbox: inbox, agent_bot: bot, status: :active)
    target = { 'integrationId' => SecureRandom.uuid, 'channelId' => SecureRandom.uuid, 'inboxId' => inbox.id, 'transport' => 'CENTRAL_TRANSPORT',
               'provider' => nil }
    record = JrcFlowNativeRegistration.create!(account: account, created_by: admin, account_user: AccountUser.find_by!(account: account, user: admin),
                                               broker_origin: 'https://broker.example.test', host_origin: 'https://host.example.test',
                                               organization_id: SecureRandom.uuid, challenge_id: SecureRandom.uuid,
                                               broker_registration_id: SecureRandom.uuid, broker_registration_revision: 1,
                                               credential_id: SecureRandom.uuid, credential_revision: 1, destination_revision: 1,
                                               account_credential_version: 1, tuple: { 'targets' => [target] }, state: 'ACTIVE',
                                               callback_digest: Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)),
                                               expires_at: 1.hour.from_now,
                                               credential_expires_at: 1.hour.from_now, encrypted_outbound_credential: 'synthetic-only')
    record.bindings.create!(account: account, inbox: inbox, integration_id: target['integrationId'], channel_id: target['channelId'],
                            transport: 'CENTRAL_TRANSPORT', registration_revision: record.revision)
    scope = fence
    epoch = scope.epochs.create!(
      registration: record, organization_id: record.organization_id, integration_id: target['integrationId'],
      channel_id: target['channelId'], cutover_id: SecureRandom.uuid, cutover_revision: 1, registration_revision: record.revision,
      generation: scope.generation, expected_owner_revision: 0, state: 'DRAINED', lease_token: SecureRandom.uuid,
      lease_until: 30.seconds.from_now, broker_agent_bot_id: bot.id, broker_agent_bot_callback: bot.outgoing_url
    )
    scope.update!(current_epoch_id: epoch.id)
    [bot, scope, epoch, record]
  end

  it 'blocks message and assignment after activation while retaining labels on the exact Inbox' do
    conversation
    team = create(:team, account: account)
    label = account.labels.create!(title: "native-#{SecureRandom.hex(4)}")
    value = rule([{ action_name: 'send_message', action_params: ['Must not send'] },
                  { action_name: 'assign_team', action_params: [team.id] }, { action_name: 'add_label', action_params: [label.title] }])
    fence
    value.update!(active: true)
    expect { AutomationRules::ActionService.new(value, account, conversation).perform }.not_to change(Message, :count)
    expect(conversation.reload.team_id).to be_nil
    expect(conversation.label_list).to include(label.title)
  end

  it 'keeps the existing message action operational in another Inbox' do
    conversation
    fence
    other = create(:channel_api, account: account).inbox
    target = create(:conversation, account: account, inbox: other)
    value = rule([{ action_name: 'send_message', action_params: ['Other Inbox allowed'] }])
    expect { AutomationRules::ActionService.new(value, account, target).perform }.to change { target.messages.count }.by(1)
  end

  it 'publishes the Message ID receipt before commit and retains pending until actual delivery' do
    message = native_message
    effect = JrcFlowOwnershipEffect.find_by!(message_id: message.id, kind: 'MESSAGE')
    expect(message.status).to eq('sent') # Host default is not a provider receipt.
    expect(message.content_attributes['jrc_native_delivery']).to eq('queued')
    expect(effect.state).to eq('QUEUED')
    JrcFlows::OwnershipEffects.refresh_message!(message.id)
    expect(effect.reload.state).to eq('QUEUED')
    described_class.delivery(message) do
      expect(ApplicationRecord.connection.transaction_open?).to be(false)
      message.update!(status: :delivered) # Synthetic provider receipt, not installed proof.
    end
    expect(effect.reload.state).to eq('CONFIRMED')
  end

  it 'cancels queued delivery after fence without calling the provider' do
    message = native_message
    fence
    job = SendReplyJob.new
    expect(job).not_to receive(:deliver)
    job.perform(message.id)
    expect(message.reload.status).to eq('failed')
    expect(JrcFlowOwnershipEffect.find_by!(message_id: message.id, kind: 'MESSAGE').state).to eq('CANCELED')
  end

  it 'retains UNKNOWN after transport failure and refuses a repeated provider call' do
    message = native_message
    expect { described_class.delivery(message) { raise Timeout::Error } }.to raise_error(Timeout::Error)
    expect(JrcFlowOwnershipEffect.where(state: 'UNKNOWN').exists?).to be(true)
    expect { described_class.delivery(message) { raise 'must not dispatch again' } }.not_to raise_error
    expect(JrcFlowOwnershipEffect.find_by!(message_id: message.id, kind: 'MESSAGE').state).to eq('QUEUED')
    scope = fence
    described_class.quiesce_messages!(scope)
    expect(JrcFlowOwnershipEffect.find_by!(message_id: message.id, kind: 'MESSAGE').state).to eq('QUEUED')
    expect(JrcFlowOwnershipEffect.where(state: 'UNKNOWN').exists?).to be(true)
    expect(JrcFlows::NativeOwnership.new.counts(scope)[:effects]).to be_positive
  end

  it 'rejects reconfiguration and reactivation of policy after the fence' do
    bot = create(:agent_bot, account: account, outgoing_url: 'https://legacy.example.test/events')
    AgentBotInbox.create!(account: account, inbox: inbox, agent_bot: bot)
    conversation.update!(assignee_agent_bot_id: nil)
    fence
    expect do
      bot.update!(outgoing_url: 'https://changed.example.test/events')
    end.to raise_error(ActiveRecord::StatementInvalid, /JRC_NATIVE_INBOX_FENCED/)
    expect { inbox.update!(greeting_enabled: true) }.to raise_error(ActiveRecord::StatementInvalid, /JRC_NATIVE_INBOX_FENCED/)
    expect { conversation.update!(assignee_agent_bot_id: bot.id) }.to raise_error(ActiveRecord::StatementInvalid, /JRC_NATIVE_INBOX_FENCED/)
    expect { AgentBotInbox.where(inbox_id: inbox.id).delete_all }.to raise_error(ActiveRecord::StatementInvalid, /JRC_NATIVE_INBOX_FENCED/)
  end

  it 'allows only the exact canonical callback and rejects another bot or a revoked registration' do
    bot, _scope, _epoch, record = canonical_bot
    expect(described_class.broker_bot?(inbox, bot)).to be(true)
    other = create(:agent_bot, account: account, outgoing_url: bot.outgoing_url)
    expect(described_class.broker_bot?(inbox, other)).to be(false)
    record.update!(state: 'REVOKED', revoked_at: Time.current, callback_digest: nil, encrypted_pending_callback: nil,
                   encrypted_outbound_credential: nil)
    expect(described_class.broker_bot?(inbox, bot)).to be(false)
  end

  it 'serializes configuration against the scope fence so both cannot succeed' do
    bot = create(:agent_bot, account: account, outgoing_url: 'https://old.example.test/events')
    AgentBotInbox.create!(account: account, inbox: inbox, agent_bot: bot)
    scope = JrcFlowOwnershipScope.create!(scope_key: JrcFlows::OwnershipGuard.key('https://host.example.test', account.id, inbox.id),
                                          host_origin: 'https://host.example.test', account_id: account.id, inbox_id: inbox.id)
    outcomes = concurrently([
                              lambda do
                                JrcFlowOwnershipScope.find(scope.id).with_lock do |_locked|
                                  described_class.verify_pair!(Inbox.find(inbox.id), bot.id, 'https://old.example.test/events')
                                  JrcFlowOwnershipScope.find(scope.id).update!(state: 'FENCED')
                                end
                                :fenced
                              end,
                              lambda do
                                AgentBot.find(bot.id).update!(outgoing_url: 'https://new.example.test/events')
                                :changed
                              end
                            ])
    expect(outcomes.count { |value| %i[fenced changed].include?(value) }).to eq(1)
    if outcomes.include?(:fenced)
      expect(bot.reload.outgoing_url).to eq('https://old.example.test/events')
    else
      expect(scope.reload.state).to eq('LEGACY')
    end
  end

  it 'rejects concurrent bots under the explicit null QR pair' do
    create(:agent_bot, account: account).tap { |bot| AgentBotInbox.create!(account: account, inbox: inbox, agent_bot: bot) }
    expect { described_class.verify_pair!(inbox, nil, nil) }.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'dispatches the canonical event outside a transaction and refuses stale epoch metadata' do
    bot, scope, epoch = canonical_bot
    Timeout.timeout(5) do
      described_class.api_actor(inbox, bot, reference: "canonical-assignment:#{SecureRandom.uuid}") do
        conversation.update!(assignee_agent_bot_id: bot.id)
      end
    end
    payload = { event: 'fixture_event' }
    expect(Webhooks::Trigger).to receive(:execute).once do
      expect(ApplicationRecord.connection.transaction_open?).to be(false)
      true
    end
    AgentBots::WebhookJob.new.perform(
      bot.outgoing_url, payload, :agent_bot_webhook, secret: bot.secret, delivery_id: SecureRandom.uuid,
      native_account_id: account.id, native_inbox_id: inbox.id, native_bot_id: bot.id, native_epoch_id: epoch.id
    )
    expect(described_class.drain_executions(scope).where(state: %w[RUNNING UNKNOWN]).count).to eq(0)
    expect do
      AgentBots::WebhookJob.new.perform(
        bot.outgoing_url, payload, :agent_bot_webhook, secret: bot.secret, delivery_id: SecureRandom.uuid,
        native_account_id: account.id, native_inbox_id: inbox.id, native_bot_id: bot.id, native_epoch_id: epoch.id + 1
      )
    end.to raise_error(JrcFlows::OwnershipGuard::Closed)
  end

  it 'uses the authenticated API actor and does not grant a sender-ID exception' do
    conversation
    bot = create(:agent_bot, account: account)
    fence
    expect do
      described_class.api_actor(inbox, bot, reference: SecureRandom.uuid) do
        raise 'must not mutate'
      end
    end.to raise_error(JrcFlows::OwnershipGuard::Closed)
    expect(described_class.api_actor(inbox, admin, reference: SecureRandom.uuid) { :human_allowed }).to eq(:human_allowed)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         headers: { 'api_access_token' => bot.access_token.token },
         params: { content: 'Must not send', sender_type: 'AgentBot', sender_id: bot.id }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(conversation.messages.where(content: 'Must not send')).not_to exist
  end

  it 'verifies the installed database function instead of trusting only a trigger name' do
    expect(described_class.installed!).to be(true)
    source = ApplicationRecord.connection.select_value("SELECT prosrc FROM pg_proc WHERE oid='jrc_native_responder_config_fence()'::regprocedure")
    begin
      ApplicationRecord.connection.execute(
        'CREATE OR REPLACE FUNCTION jrc_native_responder_config_fence() ' \
        'RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NEW; END; $$'
      )
      expect { described_class.installed! }.to raise_error(JrcFlows::OwnershipGuard::Closed, /POLICY_CHANGED/)
    ensure
      ApplicationRecord.connection.execute(File.read(Rails.root.join('db/functions/20261015160000_native_responder_config_fence.sql')))
    end
    expect(source).to be_present
  end
end
