require 'rails_helper'

RSpec.describe Conversations::SharedInboxRouting do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  it 'recognizes ordinary local inboxes without native or JRC automation' do
    expect(described_class.new(account: account, user: agent, inbox_ids: [inbox.id]).perform).to eq([inbox.id])
  end

  it 'observes native activation freshly on the next request' do
    expect(described_class.new(account: account, user: agent, inbox_ids: [inbox.id]).perform).to eq([inbox.id])
    create(:agent_bot_inbox, inbox: inbox, status: :active)
    expect(described_class.new(account: account, user: agent, inbox_ids: [inbox.id]).perform).to be_empty
  end

  it 'uses configured local flows before any run exists and ignores remote-host inbox-id coincidences' do
    flow = JrcFlow.new(account: account, name: 'Synthetic routing', status: 'active', graph: {}, settings: { inbox_ids: [inbox.id] })
    flow.save!(validate: false)
    expect(described_class.new(account: account, user: agent, inbox_ids: [inbox.id]).perform).to be_empty
    flow.update_columns(status: 'paused')
    expect(described_class.new(account: account, user: agent, inbox_ids: [inbox.id]).perform).to eq([inbox.id])
  end

  it 'fails closed for a bound Broker without a fresh compatible proof' do
    api_inbox = create(:channel_api, account: account).inbox
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: api_inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    allow(JrcBroker::RoutingContext).to receive(:new).and_return(double(perform: {}))
    expect(described_class.new(account: account, user: agent, inbox_ids: [api_inbox.id]).perform).to be_empty
  end

  [nil, 'ROUTED', 'UNKNOWN', 'NONE'].each do |state|
    it "keeps revoked native bindings subject to fresh remote proof #{state.inspect}" do
      registration = JrcFlowNativeRegistration.create!(account: account, created_by: agent,
                                                       broker_origin: 'https://broker.example.test', host_origin: 'https://host.example.test',
                                                       organization_id: SecureRandom.uuid, challenge_id: SecureRandom.uuid,
                                                       credential_id: SecureRandom.uuid, credential_revision: 1, destination_revision: 1,
                                                       account_credential_version: 1, tuple: {}, state: 'REVOKED', revoked_at: Time.current,
                                                       expires_at: 1.hour.from_now, credential_expires_at: 1.hour.from_now)
      binding = registration.bindings.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid,
                                              channel_id: SecureRandom.uuid, transport: 'CENTRAL_TRANSPORT', registration_revision: 1)
      proof = state ? { inbox.id => state } : {}
      allow(JrcBroker::RoutingContext).to receive(:new).with(account: account, user: agent, bindings: [binding]).and_return(double(perform: proof))
      expect(described_class.new(account: account, user: agent, inbox_ids: [inbox.id]).perform).to eq(state == 'NONE' ? [inbox.id] : [])
      expect(JrcBroker::RoutingContext).to have_received(:new)
    end
  end

  it 'rechecks local bot activation after the remote read before granting sharing' do
    api_inbox = create(:channel_api, account: account).inbox
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
    JrcBrokerInboxBinding.create!(account: account, inbox: api_inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    remote = double
    allow(JrcBroker::RoutingContext).to receive(:new).and_return(remote)
    allow(remote).to receive(:perform) do
      create(:agent_bot_inbox, inbox: api_inbox, status: :active)
      { api_inbox.id => 'NONE' }
    end
    expect(described_class.new(account: account, user: agent, inbox_ids: [api_inbox.id]).perform).to be_empty
  end
end
