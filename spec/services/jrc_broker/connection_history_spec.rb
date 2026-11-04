require 'rails_helper'

RSpec.describe JrcBroker::ConnectionHistory do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:other_admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:binding) do
    JrcBrokerInboxBinding.create!(account: account, inbox: inbox, integration_id: SecureRandom.uuid, instance_id: SecureRandom.uuid)
  end
  let(:history) { described_class.new(binding, user: admin) }
  let(:health) do
    { 'instanceStatus' => 'CONNECTED', 'integrationStatus' => 'READY', 'identityApproved' => true,
      'identityStatus' => 'CONFIRMED', 'identityRevision' => 2, 'checkedAt' => '2026-11-04T12:00:02Z' }
  end

  it 'ignores an older status response without rolling back health or inventing a disconnect event' do
    history.observe!(health)

    expect do
      history.observe!(health.merge('instanceStatus' => 'DISCONNECTED', 'checkedAt' => '2026-11-04T12:00:01Z'))
    end.not_to change(JrcBrokerConnectionEvent, :count)

    expect(binding.reload.connection_state['health']).to include('instanceStatus' => 'CONNECTED', 'checkedAt' => '2026-11-04T12:00:02Z')
  end

  it 'ignores identity mismatch from an older response' do
    history.observe!(health)

    history.observe!(health.merge('identityStatus' => 'CONFIRMATION_REQUIRED', 'identityRevision' => 1,
                                 'checkedAt' => '2026-11-04T12:00:01Z'))

    expect(JrcBrokerConnectionEvent.where(inbox: inbox, event_type: 'NUMBER_MISMATCH')).to be_empty
    expect(binding.reload.connection_state['health']).to include('identityStatus' => 'CONFIRMED', 'identityRevision' => 2)
  end

  it 'compares absolute times rather than the timestamp string ordering' do
    history.observe!(health)

    history.observe!(health.merge('instanceStatus' => 'DISCONNECTED', 'checkedAt' => '2026-11-04T09:00:03-03:00'))

    expect(binding.reload.connection_state['health']).to include('instanceStatus' => 'DISCONNECTED',
                                                               'checkedAt' => '2026-11-04T09:00:03-03:00')
    expect(JrcBrokerConnectionEvent.where(inbox: inbox, event_type: 'DISCONNECTED').count).to eq(1)
  end

  it 'preserves transitions when the provider has only second-resolution timestamps' do
    history.observe!(health.merge('instanceStatus' => 'DISCONNECTED'))

    history.observe!(health)

    expect(binding.reload.connection_state['health']['instanceStatus']).to eq('CONNECTED')
    expect(JrcBrokerConnectionEvent.where(inbox: inbox, event_type: 'CONNECTED').count).to eq(1)
  end

  it 'continues to process the first observation of a legacy cache without a timestamp' do
    binding.update!(connection_state: { 'health' => health.except('checkedAt').merge('instanceStatus' => 'DISCONNECTED') })

    history.observe!(health)

    expect(binding.reload.connection_state['health']).to include('instanceStatus' => 'CONNECTED', 'checkedAt' => '2026-11-04T12:00:02Z')
  end

  it 'rejects malformed or non-string timestamps with a typed Broker error without changing valid health' do
    history.observe!(health)
    previous = binding.reload.connection_state.deep_dup

    ['not-a-time', false, 42, {}, []].each do |timestamp|
      expect { history.observe!(health.merge('checkedAt' => timestamp)) }.to raise_error do |error|
        expect(error.class.name).to eq('JrcBroker::Client::Error')
        expect(error.message).to eq('JRC_BROKER_INVALID_RESPONSE')
      end
    end

    expect(binding.reload.connection_state).to eq(previous)
  end

  it 'preserves a valid watermark when a compatible legacy observation omits its timestamp' do
    history.observe!(health)
    history.observe!(health.except('checkedAt'))
    history.observe!(health.merge('instanceStatus' => 'DISCONNECTED', 'checkedAt' => '2026-11-04T12:00:01Z'))

    expect(binding.reload.connection_state['health']).to include('instanceStatus' => 'CONNECTED', 'checkedAt' => '2026-11-04T12:00:02Z')
    expect(JrcBrokerConnectionEvent.where(inbox: inbox, event_type: 'DISCONNECTED')).to be_empty
  end

  it 'replaces an unusable legacy watermark with a valid observation' do
    binding.update!(connection_state: { 'health' => health.merge('checkedAt' => 'legacy-unusable-timestamp') })

    history.observe!(health)

    expect(binding.reload.connection_state['health']['checkedAt']).to eq('2026-11-04T12:00:02Z')
  end

  it 'does not attach a delayed pair result to a newer attempt by another actor' do
    history.request!('pair', key: 'first-pair-intent', state: health)
    other = described_class.new(JrcBrokerInboxBinding.find(binding.id), user: other_admin)
    other.request!('pair', key: 'second-pair-intent', state: health)

    history.result!({ 'operationId' => 'first-operation', 'action' => { 'expiresAt' => '2026-11-04T12:01:00Z' } }, key: 'first-pair-intent')

    expect(binding.reload.connection_state['attempt']).to include('key' => 'second-pair-intent', 'actor_id' => other_admin.id)
    expect(binding.connection_state['attempt']).not_to have_key('operation_id')
    other.result!({ 'operationId' => 'second-operation', 'action' => { 'expiresAt' => '2026-11-04T12:02:00Z' } }, key: 'second-pair-intent')
    expect(binding.reload.connection_state['attempt']).to include('operation_id' => 'second-operation', 'actor_id' => other_admin.id)
  end

  it 'updates pairing progress only for the operation already attached to the current attempt' do
    binding.update!(connection_state: { 'attempt' => { 'key' => 'current-intent', 'actor_id' => admin.id,
                                                     'operation_id' => 'current-operation', 'expires_at' => '2026-11-04T12:01:00Z' } })

    history.result!({ 'operationId' => 'older-operation', 'action' => { 'expiresAt' => '2026-11-04T12:03:00Z' } })
    expect(binding.reload.connection_state['attempt']).to include('operation_id' => 'current-operation', 'expires_at' => '2026-11-04T12:01:00Z')

    history.result!({ 'operationId' => 'current-operation', 'action' => { 'expiresAt' => '2026-11-04T12:02:00Z' } })
    expect(binding.reload.connection_state['attempt']).to include('operation_id' => 'current-operation', 'expires_at' => '2026-11-04T12:02:00Z')
  end

  it 'does not associate uncorrelated progress with an attempt that has no operation identifier' do
    history.request!('pair', key: 'current-pair-intent', state: health)

    expect do
      history.result!({ 'operationId' => 'unknown-operation', 'action' => { 'expiresAt' => '2026-11-04T12:02:00Z' } })
    end.not_to(change { binding.reload.connection_state })
  end

  it 'still audits expiration once when repeated status observations have the same timestamp' do
    travel_to Time.utc(2026, 11, 4, 12, 2) do
      history.request!('pair', key: 'expiring-pair-intent', state: health)
      history.result!({ 'operationId' => 'expiring-operation', 'action' => { 'expiresAt' => '2026-11-04T12:01:00Z' } },
                      key: 'expiring-pair-intent')

      2.times { history.observe!(health.merge('instanceStatus' => 'DISCONNECTED')) }

      expect(JrcBrokerConnectionEvent.where(inbox: inbox, event_type: 'QR_EXPIRED').count).to eq(1)
    end
  end
end
