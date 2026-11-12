require 'rails_helper'

RSpec.describe JrcBroker::HistoryProgress do
  let(:organization_id) { SecureRandom.uuid }
  let(:channel_id) { SecureRandom.uuid }
  let(:binding) { Struct.new(:integration_id, :account_id, :inbox_id, :instance_id).new(SecureRandom.uuid, 1, 11, SecureRandom.uuid) }
  let(:integration) { Struct.new(:organization_id, :destination_revision).new(organization_id, 3) }
  let(:run) do
    { 'schemaVersion' => 2, 'id' => SecureRandom.uuid, 'organizationId' => organization_id, 'channelId' => channel_id,
      'instanceId' => binding.instance_id, 'revision' => 1, 'state' => 'RUNNING', 'capture' => 'CAPTURING',
      'persistence' => 'RUNNING', 'projection' => 'RUNNING', 'sourceTotalKnown' => false, 'lastError' => nil,
      'counts' => described_class::COUNTS.index_with { 0 } }
  end
  let(:envelope) do
    { 'schemaVersion' => 2, 'organizationId' => organization_id, 'channelId' => channel_id, 'integrationId' => binding.integration_id,
      'accountId' => 1, 'inboxId' => 11, 'destinationRevision' => 3, 'run' => run }
  end

  it 'retains only scoped scalar progress, including media custody, without raw payloads' do
    run['counts'].merge!('chats' => 2, 'capturedMessages' => 3, 'persistedMessages' => 2, 'duplicateMessages' => 1,
                         'projectedMessages' => 1, 'verifiedMedia' => 1, 'pendingMedia' => 1, 'untrusted' => 'PRIVATE_CANARY')
    result = described_class.present!(envelope.merge('private' => 'PRIVATE_CANARY'), binding: binding, integration: integration)
    expect(result['run']['counts']['chats']).to eq(2)
    expect(result['run']['counts']['pendingMedia']).to eq(1)
    expect(result.to_json).not_to include('PRIVATE_CANARY')
  end

  it 'accepts only null or an actual run object' do
    expect(described_class.present!(envelope.merge('run' => nil), binding: binding, integration: integration)['run']).to be_nil
    expect { described_class.present!(envelope.merge('run' => false), binding: binding, integration: integration) }
      .to raise_error(JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE')
  end

  it 'rejects another tenant, inbox, revision or instance instead of showing unrelated progress' do
    [{ 'organizationId' => SecureRandom.uuid }, { 'inboxId' => 12 }, { 'destinationRevision' => 4 },
     { 'run' => run.merge('instanceId' => SecureRandom.uuid) }].each do |change|
      expect { described_class.present!(envelope.merge(change), binding: binding, integration: integration) }
        .to raise_error(JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE')
    end
  end

  it 'rejects impossible counters and a completed run with pending or unavailable media' do
    run['counts']['projectedMessages'] = 1
    expect { described_class.present!(envelope, binding: binding, integration: integration) }.to raise_error(JrcBroker::Client::Error)
    run['counts']['projectedMessages'] = 0
    run.merge!('state' => 'COMPLETED', 'capture' => 'COMPLETE', 'persistence' => 'COMPLETE', 'projection' => 'COMPLETE')
    %w[pendingMedia unavailableMedia blockedRecords].each do |field|
      run['counts'][field] = 1
      expect { described_class.present!(envelope, binding: binding, integration: integration) }.to raise_error(JrcBroker::Client::Error)
      run['counts'][field] = 0
    end
    expect(described_class.present!(envelope, binding: binding, integration: integration)['run']['state']).to eq('COMPLETED')
  end
end
