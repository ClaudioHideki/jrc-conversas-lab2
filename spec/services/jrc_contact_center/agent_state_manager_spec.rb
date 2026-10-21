# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::AgentStateManager do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:manager) { described_class.new(account: account, account_user: member) }

  it 'records local intent without claiming provider confirmation or eligibility' do
    event = manager.transition(state: 'available', command_id: 'state-1', expected_state_version: '0')
    snapshot = JrcContactCenter::AgentStateSnapshot.new(account_user: member).call

    expect(event.metadata['provider_confirmed']).to be(false)
    expect(snapshot).to include(state: 'available', eligible: false, provider_confirmed: false, state_version: event.id.to_s)
  end

  it 'replays the same request without creating or closing another state' do
    event = manager.transition(state: 'available', command_id: 'state-1', expected_state_version: '0')
    replay = manager.transition(state: 'available', command_id: 'state-1', expected_state_version: '0')

    expect(replay.id).to eq(event.id)
    expect(event.reload.ended_at).to be_nil
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
  end

  it 'rejects a conflicting reuse of a command identifier' do
    manager.transition(state: 'available', command_id: 'state-1', expected_state_version: '0')

    expect do
      manager.transition(state: 'offline', command_id: 'state-1', expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'command_id_conflict')
  end

  it 'rejects an outdated state version without changing the existing event' do
    event = manager.transition(state: 'available', command_id: 'state-1', expected_state_version: '0')

    expect do
      manager.transition(state: 'offline', command_id: 'state-2', expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'state_conflict')
    expect(event.reload.ended_at).to be_nil
  end

  it 'requires a pause reason' do
    expect do
      manager.transition(state: 'paused', command_id: 'pause-1', expected_state_version: '0')
    end.to raise_error(JrcContactCenter::OperationError, 'pause_reason_required')
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'does not replace a live call state with an operator availability request' do
    event = manager.record_provider_event(state: 'in_call', occurred_at: Time.current, external_event_id: 'call-state', provider: 'jrc_pabx')

    expect do
      manager.transition(state: 'available', command_id: 'state-1', expected_state_version: event.id.to_s)
    end.to raise_error(JrcContactCenter::OperationError, 'call_active')
    expect(event.reload.ended_at).to be_nil
  end

  it 'does not regress current state when an older provider state arrives late' do
    current = manager.record_provider_event(state: 'available', occurred_at: Time.current,
                                            external_event_id: 'new-state', provider: 'jrc_pabx')
    older = manager.record_provider_event(state: 'paused', occurred_at: 1.minute.ago,
                                          external_event_id: 'old-state', provider: 'jrc_pabx')

    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).current.id).to eq(current.id)
    expect(older.ended_at).to eq(current.started_at)
    expect(current.reload.ended_at).to be_nil
  end

  it 'rejects a member from another account' do
    expect do
      described_class.new(account: create(:account), account_user: member)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not make a locally available agent eligible even with an active membership' do
    unit = JrcContactCenter::Unit.create!(account: account, code: 'SAC', name: 'SAC', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q', name: 'Queue')
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member)
    manager.transition(state: 'available', command_id: 'local-queue', expected_state_version: '0', queue_id: queue.id)

    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call).to include(
      eligible: false, eligibility_reason: 'provider_pending', eligible_queue_ids: []
    )
  end

  it 'excludes expired memberships from confirmed queue eligibility' do
    unit = JrcContactCenter::Unit.create!(account: account, code: 'SAC', name: 'SAC', kind: 'sac')
    queue = JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'Q', name: 'Queue')
    JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member,
                                              starts_at: 2.minutes.ago, ends_at: 1.minute.ago)
    manager.record_provider_event(state: 'available', occurred_at: Time.current, external_event_id: 'available-queue',
                                  provider: 'jrc_pabx', queue_id: queue.id)

    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call).to include(
      eligible: false, eligibility_reason: 'queue_membership_missing', queues: []
    )
  end
end
