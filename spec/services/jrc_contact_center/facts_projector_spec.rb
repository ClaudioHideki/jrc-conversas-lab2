# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::FactsProjector do
  let(:account) { create(:account) }
  let(:started_at) { Time.zone.parse('2026-10-15 10:00:00') }
  let(:session) do
    JrcContactCenter::CallSession.create!(account: account, correlation_id: SecureRandom.uuid, direction: 'inbound',
                                          status: 'ended', started_at: started_at, answered_at: started_at + 10.seconds,
                                          ended_at: started_at + 70.seconds,
                                          metadata: { 'jrc_f1' => { 'entry_queued_at' => started_at.iso8601,
                                                                    'offered_at' => started_at.iso8601, 'hold_seconds' => 5 } })
  end
  let(:projector) { described_class.new(account: account) }

  it 'does not count a completed session again when reconciled repeatedly' do
    projector.call(session.id)
    projector.call(session.id)

    expect(JrcContactCenter::DailyFact.where(account: account).count).to eq(1)
    expect(JrcContactCenter::DailyFact.find_by!(account: account)).to have_attributes(
      offered_count: 1, answered_count: 1, wait_seconds: 10, talk_seconds: 55, hold_seconds: 5
    )
  end

  it 'applies only the difference when a late confirmed measurement changes' do
    projector.call(session.id)
    session.reload.update_f1_data('hold_seconds' => 15)
    projector.call(session.id)

    expect(JrcContactCenter::DailyFact.find_by!(account: account)).to have_attributes(
      answered_count: 1, talk_seconds: 45, hold_seconds: 15
    )
  end

  it 'does not double count overlapping legs during a transfer' do
    session.legs.create!(account: account, direction: 'inbound', external_leg_id: 'first', status: 'ended', started_at: started_at,
                         answered_at: started_at + 10.seconds, ended_at: started_at + 50.seconds)
    session.legs.create!(account: account, direction: 'internal', external_leg_id: 'second', status: 'ended', started_at: started_at + 30.seconds,
                         answered_at: started_at + 40.seconds, ended_at: started_at + 70.seconds)
    projector.call(session.id)

    expect(JrcContactCenter::DailyFact.find_by!(account: account).talk_seconds).to eq(55)
  end

  it 'rejects a session belonging to another account' do
    foreign_projector = described_class.new(account: create(:account))

    expect { foreign_projector.call(session.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::DailyFact.count).to eq(0)
  end

  it 'does not publish a final fact for a live session' do
    session.update!(status: 'connected', ended_at: nil)
    projector.call(session.id)

    expect(JrcContactCenter::DailyFact.where(account: account)).to be_empty
  end

  it 'adds completed ACW only after the associated agent state closes' do
    agent = create(:user, account: account, role: :agent)
    member = account.account_users.find_by!(user: agent)
    manager = JrcContactCenter::AgentStateManager.new(account: account, account_user: member)
    manager.record_provider_event(state: 'acw', occurred_at: session.ended_at, external_event_id: 'acw-start', provider: 'jrc_pabx',
                                  metadata: { 'jrc_call_session_id' => session.id })
    projector.call(session.id)
    expect(JrcContactCenter::DailyFact.find_by!(account: account).acw_seconds).to eq(0)

    manager.record_provider_event(state: 'available', occurred_at: session.ended_at + 10.seconds,
                                  external_event_id: 'acw-end', provider: 'jrc_pabx')
    projector.call(session.id)

    fact = JrcContactCenter::DailyFact.find_by!(account: account)
    expect(fact.acw_seconds).to eq(10)
    expect(fact.data).to include('acw_completed_count' => 1, 'acw_measured_seconds' => 10)
  end

  it 'rolls back the agent transition if its completed ACW projection fails' do
    agent = create(:user, account: account, role: :agent)
    member = account.account_users.find_by!(user: agent)
    manager = JrcContactCenter::AgentStateManager.new(account: account, account_user: member)
    acw = manager.record_provider_event(state: 'acw', occurred_at: session.ended_at, external_event_id: 'acw-start', provider: 'jrc_pabx',
                                        metadata: { 'jrc_call_session_id' => session.id })
    failing_projector = instance_double(described_class)
    allow(described_class).to receive(:new).with(account: account).and_return(failing_projector)
    allow(failing_projector).to receive(:call).with(session.id).and_raise('projection_failed')

    expect do
      manager.transition(state: 'available', command_id: 'acw-close', expected_state_version: acw.id.to_s)
    end.to raise_error(RuntimeError, 'projection_failed')

    expect(acw.reload.ended_at).to be_nil
    expect(JrcContactCenter::AgentStateEvent.where(account: account).count).to eq(1)
  end
end
