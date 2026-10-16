require 'rails_helper'

RSpec.describe 'Native ownership durable guard and drain', type: :request do
  self.use_transactional_tests = false
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox.tap { |item| item.update!(greeting_enabled: false, enable_auto_assignment: false) } }
  let(:organization) { SecureRandom.uuid }
  let(:integration) { SecureRandom.uuid }
  let(:callback) { SecureRandom.urlsafe_base64(32) }
  let(:origin) { 'https://host.example.test' }
  let(:request_tuple) do
    { 'organizationId' => organization, 'origin'=>origin, 'accountId'=>account.id, 'inboxId'=>inbox.id, 'destinationRevision'=>2,
      'accountCredentialVersion' => 3, 'integrationId'=>integration, 'cutoverId'=>SecureRandom.uuid,
      'cutoverRevision'=>1, 'expectedOwnerRevision'=>0, 'originCapabilityRevision'=>1,
      'expectedAgentBotId'=>nil, 'expectedAgentBotCallback'=>nil, 'expectedHostSourceSha'=>'8'*40,
      'expectedHostImageDigest'=>'sha256:'+('9'*64), 'nonce'=>SecureRandom.uuid,
      'externalActorId'=>admin.id.to_s, 'brokerActorId'=>nil, 'leaseToken'=>SecureRandom.uuid,
      'leaseExpiresAt'=>(ApplicationRecord.connection.select_value('SELECT clock_timestamp()').to_time+30.seconds).utc.iso8601(6) }
  end
  let(:identity) do
    lambda { |request|
      { source: request['expectedHostSourceSha'], image: request['expectedHostImageDigest'], paths: JrcFlows::OwnershipGuard::PATHS.keys }
    }
  end

  before do
    account.enable_features!('jrc_flows')
    create(:inbox_member, inbox: inbox, user: admin)
    @record=JrcFlowNativeRegistration.create!(
      account: account, created_by: admin, account_user: AccountUser.find_by!(account: account, user: admin),
      broker_origin: 'https://broker.example.test', host_origin: origin, organization_id: organization,
      challenge_id: SecureRandom.uuid, broker_registration_id: SecureRandom.uuid, broker_registration_revision: 1,
      credential_id: SecureRandom.uuid, credential_revision: 1, destination_revision: 2, account_credential_version: 3,
      tuple: { 'targets'=>[{ 'integrationId'=>integration, 'channelId'=>SecureRandom.uuid, 'inboxId'=>inbox.id,
                            'transport'=>'CENTRAL_TRANSPORT', 'provider'=>nil }] },
      expires_at: 1.hour.from_now, credential_expires_at: 1.hour.from_now
    )
    @record.update!(state: 'ACTIVE', callback_digest: Digest::SHA256.hexdigest(callback), encrypted_outbound_credential: 'synthetic-only')
    target=@record.tuple.fetch('targets').first
    @record.bindings.create!(account: account, inbox: inbox, integration_id: integration, channel_id: target.fetch('channelId'),
                             transport: 'CENTRAL_TRANSPORT', registration_revision: @record.revision)
  end

  around { |example| with_modified_env(JRC_FLOWS_ENABLED: 'true', JRC_FLOWS_EXTERNAL_BETA: 'true', FRONTEND_URL: 'https://host.example.test') { example.run } }

  def control = JrcFlows::NativeOwnership.new(identity: identity)
  def close! = control.fence!(registration: @record, request: request_tuple)

  it 'closes exact Account/Inbox admission and rejects foreign registration tuples' do
    result=close!
    expect(result).to include('admissionClosed'=>true, 'liveRuns'=>0, 'legacyJobs'=>0, 'uncertainEffects'=>0)
    expect(JrcFlows::OwnershipGuard.allowed_local?(account.id, inbox.id)).to eq(false)
    other=create(:channel_api, account: account).inbox
    expect(JrcFlows::OwnershipGuard.allowed_local?(account.id, other.id)).to eq(true)
    expect do
      control.observe!(registration: @record,
                       request: request_tuple.merge('organizationId'=>SecureRandom.uuid))
    end.to raise_error(JrcFlows::NativeOwnership::Denied)
  end

  it 'blocks remote connections in another source tenant targeting the same origin/Account/Inbox' do
    close!
    foreign=create(:account)

    connection=JrcFlowConnection.create!(account: foreign, name: 'Synthetic remote', base_url: origin, remote_account_id: account.id,
                                         inbox_ids: [inbox.id], enabled: true)
    expect(JrcFlows::OwnershipGuard.allowed_remote?(connection, inbox.id)).to eq(false)
    expect(JrcFlows::OwnershipGuard.allowed_remote?(connection, inbox.id+999)).to eq(false)
    unrelated=JrcFlowConnection.create!(account: create(:account), name: 'Unrelated destination', base_url: origin, remote_account_id: account.id,
                                        inbox_ids: [inbox.id+999], enabled: true)
    expect(JrcFlows::OwnershipGuard.allowed_remote?(unrelated, inbox.id+999)).to eq(true)
  end

  it 'retains an external UNKNOWN effect after the runner transaction rolls back and refuses repeat' do
    reference="synthetic:#{SecureRandom.uuid}"
    expect do
      ApplicationRecord.transaction do
        JrcFlows::OwnershipGuard.with_local(account.id, inbox.id, path: 'runner', reference: reference) do
          JrcFlows::OwnershipEffects.perform(reference: reference, kind: 'EXTERNAL') { 'synthetic ACK' }
          raise 'synthetic rollback'
        end
      end
    end.to raise_error('synthetic rollback')
    expect(JrcFlowOwnershipEffect.find_by!(effect_reference: reference).state).to eq('UNKNOWN')
    expect { close! }.to raise_error(JrcFlows::NativeOwnership::NotDrained)
    expect do
      JrcFlows::OwnershipGuard.with_local(account.id, inbox.id, path: 'runner', reference: reference) do
        raise 'must never repeat'
      end
    end.to raise_error(JrcFlows::OwnershipGuard::Closed)
  end

  it 'keeps queued outgoing delivery blocking until actual sent status, never channel_processed alone' do
    conversation=create(:conversation, account: account, inbox: inbox)
    message=create(:message, account: account, conversation: conversation, message_type: :outgoing,
                             content_attributes: { 'jrc_flow_run_id'=>123, 'jrc_flow_delivery'=>'channel_processed' }, status: :sent)
    expect { close! }.to raise_error(JrcFlows::NativeOwnership::NotDrained)
    message.update!(status: :delivered)
    expect(control.observe!(registration: @record, request: request_tuple)).to include('uncertainEffects'=>0)
  end

  it 'atomically retires an unaccepted epoch and prevents late fence acceptance' do
    bot=create(:agent_bot, account: account, outgoing_url: 'https://broker.example.test/events')
    AgentBotInbox.create!(account: account, inbox: inbox, agent_bot: bot, status: :active)
    request_tuple.merge!('expectedAgentBotId'=>bot.id, 'expectedAgentBotCallback'=>bot.outgoing_url)
    retired=control.retire!(registration: @record, request: request_tuple)
    expect(retired).to include('outcome'=>'NOT_STARTED_RETIRED')
    expect(control.retire!(registration: @record, request: request_tuple)).to eq(retired)
    expect { close! }.to raise_error(JrcFlows::NativeOwnership::Denied)
    expect(JrcFlows::OwnershipGuard.allowed_local?(account.id, inbox.id)).to eq(true)
  end

  it 'fails reopen without independently observed Broker drain and preserves the closed epoch' do
    close!
    expect { control.reopen!(registration: @record, request: request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
    expect(JrcFlows::OwnershipGuard.allowed_local?(account.id, inbox.id)).to eq(false)
  end

  it 'denies missing installed guard identity and applies actual dispatch/resume/recovery barriers' do
    expect { JrcFlows::NativeOwnership.new.fence!(registration: @record, request: request_tuple) }.to raise_error(JrcFlows::NativeOwnership::Denied)
    close!
    conversation=create(:conversation, account: account, inbox: inbox)
    JrcFlows::DispatchJob.perform_now(account.id, conversation.id, 'conversation_created', SecureRandom.uuid)
    JrcFlows::RecoveryJob.perform_now
    expect(JrcFlowRun.where(conversation: conversation)).not_to exist
    expect(JrcFlows::OwnershipGuard::PATHS.length).to eq(19)
  end
end
