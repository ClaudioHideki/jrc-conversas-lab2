# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::CallJourney do
  let(:account) { create(:account) }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'SAC', name: 'National SAC', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'NATIONAL', name: 'National queue') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:started_at) { Time.zone.parse('2026-10-15 10:00:00') }

  it 'reconciles a single call with queue, offer, answer, hold and closure without replaying facts' do
    steps = [
      ['call.created', 0, {}], ['queue.entered', 1, { queue_id: queue.id }],
      ['call.offered', 5, { leg_id: 'agent-leg', account_user_id: member.id, queue_id: queue.id }],
      ['call.answered', 10, { leg_id: 'agent-leg' }], ['call.held', 20, { leg_id: 'agent-leg' }],
      ['call.resumed', 30, { leg_id: 'agent-leg' }], ['call.ended', 70, {}]
    ]
    steps.each_with_index do |(type, seconds, body), index|
      event = JrcContactCenter::EventIngestor.new(account: account).call(
        { schema_version: '1.0', event_id: "step-#{index}", event_type: type, occurred_at: (started_at + seconds.seconds).iso8601,
          provider: 'jrc_pabx', correlation_id: 'call-1', call_session_id: 'provider-call-1', payload: body }, signature_verified: true
      ).record
      JrcContactCenter::EventReconciler.new(event_record: event).call
      expect(event.reload.status).to eq('processed'), event.last_error
      JrcContactCenter::EventReconciler.new(event_record: event).call
    end

    session = JrcContactCenter::CallSession.find_by!(account: account)
    expect(session).to have_attributes(status: 'ended', current_queue_id: queue.id)
    expect(session.legs.count).to eq(1)
    expect(session.legs.first).to have_attributes(status: 'ended', answered_at: started_at + 10.seconds)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call[:state]).to eq('acw')
    expect(JrcContactCenter::DailyFact.find_by!(account: account)).to have_attributes(
      offered_count: 1, answered_count: 1, wait_seconds: 9, talk_seconds: 50, hold_seconds: 10
    )
  end

  it 'rolls back a journey referencing a queue from another account' do
    session = JrcContactCenter::CallSession.create!(account: account, correlation_id: 'call-1', direction: 'inbound', started_at: started_at)
    foreign = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign, code: 'SAC', name: 'Foreign SAC', kind: 'sac')
    foreign_queue = JrcContactCenter::Queue.create!(account: foreign, unit: foreign_unit, code: 'Q', name: 'Foreign queue')
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: 'foreign-queue', event_type: 'queue.entered', occurred_at: (started_at + 1.second).iso8601,
        provider: 'jrc_pabx', correlation_id: 'call-1', payload: { queue_id: foreign_queue.id } }, signature_verified: true
    ).record

    JrcContactCenter::EventReconciler.new(event_record: event).call

    expect(event.reload.status).to eq('failed')
    expect(session.reload).to have_attributes(status: 'created', current_queue_id: nil)
    expect(session.f1_data).to eq({})
  end

  it 'releases the local ringing state after an unanswered call without claiming provider availability' do
    steps = [['call.created', 0, {}], ['call.offered', 1, { leg_id: 'missed-leg', account_user_id: member.id }], ['call.ended', 10, {}]]
    steps.each_with_index do |(type, seconds, body), index|
      event = JrcContactCenter::EventIngestor.new(account: account).call(
        { schema_version: '1.0', event_id: "missed-#{index}", event_type: type, occurred_at: (started_at + seconds.seconds).iso8601,
          provider: 'jrc_pabx', correlation_id: 'missed-call', payload: body }, signature_verified: true
      ).record
      JrcContactCenter::EventReconciler.new(event_record: event).call
      expect(event.reload.status).to eq('processed'), event.last_error
    end
    state = JrcContactCenter::AgentStateSnapshot.new(account_user: member).call
    expect(state).to include(state: 'unavailable', provider_confirmed: false, eligible: false)

    JrcContactCenter::AgentStateManager.new(account: account, account_user: member)
                                       .transition(state: 'available', command_id: 'after-missed', expected_state_version: state[:state_version])

    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call).to include(state: 'available', eligible: false)
  end

  it 'corrects the final fact when an answered transfer leg arrives after the root call ended' do
    last_state_at = (started_at + 70.seconds).iso8601
    session = JrcContactCenter::CallSession.create!(account: account, correlation_id: 'late-leg', direction: 'inbound', status: 'ended',
                                                    started_at: started_at, answered_at: started_at + 10.seconds,
                                                    ended_at: started_at + 70.seconds, metadata: { 'jrc_f1' => { 'state_at' => last_state_at } })
    session.legs.create!(account: account, direction: 'inbound', external_leg_id: 'first', status: 'transferred', started_at: started_at,
                         answered_at: started_at + 10.seconds, ended_at: started_at + 40.seconds)
    session.legs.create!(account: account, direction: 'internal', external_leg_id: 'second', status: 'ended',
                         started_at: started_at + 40.seconds, ended_at: started_at + 70.seconds)
    JrcContactCenter::FactsProjector.new(account: account).call(session.id)
    event = JrcContactCenter::EventIngestor.new(account: account).call(
      { schema_version: '1.0', event_id: 'late-answer', event_type: 'call.leg.answered', occurred_at: (started_at + 45.seconds).iso8601,
        provider: 'jrc_pabx', correlation_id: session.correlation_id, payload: { leg_id: 'second' } }, signature_verified: true
    ).record

    JrcContactCenter::EventReconciler.new(event_record: event).call

    expect(event.reload.status).to eq('processed'), event.last_error
    expect(session.reload.status).to eq('ended')
    expect(JrcContactCenter::DailyFact.find_by!(account: account)).to have_attributes(answered_count: 1, talk_seconds: 55)
  end
end
