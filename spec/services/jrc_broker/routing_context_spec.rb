require 'rails_helper'

RSpec.describe JrcBroker::RoutingContext do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let!(:integration) do
    JrcBrokerIntegration.create!(account: account, broker_origin: 'https://broker.example.test', organization_id: SecureRandom.uuid,
                                destination_revision: 1, encrypted_control_key: 'synthetic-not-used')
  end
  let(:binding) { JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid) }
  let(:client) { instance_double(JrcBroker::Client) }
  let(:payload) do
    { 'schemaVersion' => 1, 'organizationId' => integration.organization_id, 'accountId' => account.id,
      'destinationRevision' => 1, 'checkedAt' => Time.current.iso8601,
      'data' => [{ 'integrationId' => binding.integration_id, 'channelId' => SecureRandom.uuid, 'inboxId' => inbox.id,
                   'state' => 'NONE', 'ownerRevision' => nil, 'bindingRevision' => nil }] }
  end

  before do
    allow(JrcBroker::Configuration).to receive(:enabled?).and_return(true)
    allow(JrcBroker::Context).to receive(:new).with(account: account, user: agent).and_return(double(client: client))
    allow(client).to receive(:routing_context).with([binding.integration_id]).and_return(payload)
  end

  it 'accepts only the fresh account and exact requested bindings, with no health or audit writes' do
    expect(client).not_to receive(:status)
    expect do
      expect(described_class.new(account: account, user: agent, bindings: [binding]).perform).to eq(inbox.id => 'NONE')
    end.not_to change(JrcBrokerConnectionEvent, :count)
  end

  it 'does not reuse a prior NONE after a timeout on the next request' do
    expect(described_class.new(account: account, user: agent, bindings: [binding]).perform).to eq(inbox.id => 'NONE')
    allow(client).to receive(:routing_context).and_raise(JrcBroker::Client::Error.new('JRC_BROKER_UNAVAILABLE', status: 503))
    expect(described_class.new(account: account, user: agent, bindings: [binding]).perform).to eq({})
  end

  ['not-a-timestamp', 42, nil].each do |timestamp|
    it "rejects malformed timestamp #{timestamp.inspect}" do
      payload['checkedAt'] = timestamp
      expect(described_class.new(account: account, user: agent, bindings: [binding]).perform).to eq({})
    end
  end

  it 'rejects stale observations, wrong accounts, revisions and duplicate rows' do
    service = described_class.new(account: account, user: agent, bindings: [binding])
    invalid = [payload.merge('checkedAt' => 1.hour.ago.iso8601), payload.merge('accountId' => account.id + 1),
               payload.merge('destinationRevision' => 2), payload.merge('organizationId' => SecureRandom.uuid),
               payload.merge('data' => payload['data'] * 2)]
    invalid.each do |value|
      allow(client).to receive(:routing_context).and_return(value)
      expect(service.perform).to eq({})
    end
  end

  it 'rejects a local rebind committed while the remote request was in flight' do
    allow(client).to receive(:routing_context) do
      binding.update!(integration_id: SecureRandom.uuid)
      payload
    end
    expect(described_class.new(account: account, user: agent, bindings: [binding]).perform).to eq({})
  end

  it 'revalidates multiple bindings with one table query rather than one lookup per inbox' do
    second_inbox = create(:channel_api, account: account).inbox
    second = JrcBrokerInboxBinding.create!(account: account, inbox: second_inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
    response = payload.merge('data' => payload['data'] + [{ 'integrationId' => second.integration_id, 'channelId' => SecureRandom.uuid,
                                                        'inboxId' => second_inbox.id, 'state' => 'NONE', 'ownerRevision' => nil, 'bindingRevision' => nil }])
    expect(client).to receive(:routing_context).with([binding.integration_id, second.integration_id].sort).once.and_return(response)
    reads = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, event|
      reads << event[:sql] if event[:sql].match?(/SELECT.*FROM "jrc_broker_inbox_bindings"/i)
    end
    begin
      result = described_class.new(account: account, user: agent, bindings: [binding, second]).perform
      expect(result).to eq(inbox.id => 'NONE', second_inbox.id => 'NONE')
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    expect(reads.size).to eq(1)
  end
end
