require 'rails_helper'

RSpec.describe JrcContactCenter::AgentStateManager do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:manager) { described_class.new(account: account, account_user: member) }
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago)
  end
  let!(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, direction: 'inbound',
                                      status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
  end
  let(:record) do
    call.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.pending.find_by!(call_session: call, account_user: member)
  end
  let(:snapshot) { JrcContactCenter::AgentStateSnapshot.new(account_user: member) }

  before { account.enable_features!('jrc_contact_center') }

  it 'does not interrupt a real connected leg to start an operator pause' do
    before = member.reload.availability
    expect do
      manager.transition(state: 'paused', reason_code: 'lunch', command_id: SecureRandom.uuid, expected_state_version: snapshot.version)
    end.to raise_error(JrcContactCenter::OperationError, 'call_active')
    expect(call.reload.status).to eq('connected')
    expect(leg.reload.status).to eq('connected')
    expect(member.reload.availability).to eq(before)
    expect(JrcContactCenter::AgentStateEvent.where(account_user: member)).to be_empty
  end

  it 'keeps a terminated call in ACW and preserves its draft and native availability instead of starting the pause' do
    record.update!(notes: 'SYNTHETIC pending private draft')
    before = member.reload.availability
    event = snapshot.current
    expect do
      manager.transition(state: 'paused', reason_code: 'lunch', command_id: SecureRandom.uuid, expected_state_version: event.id.to_s)
    end.to raise_error(JrcContactCenter::OperationError, 'tabulation_pending')
    expect(record.reload).to have_attributes(completed_at: nil, notes: 'SYNTHETIC pending private draft')
    expect(member.reload.availability).to eq(before)
    expect(event.reload.ended_at).to be_nil
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).current.id).to eq(event.id)
  end

  it 'continues blocking a pause after the ACW clock expires without completing or deleting answers' do
    record.update!(notes: 'SYNTHETIC overdue private draft')
    travel_to(record.started_at + record.acw_limit_seconds.seconds + 5.seconds) do
      record.operational_payload
      expect(record.reload.overdue).to be(true)
      expect do
        manager.transition(state: 'paused', reason_code: 'lunch', command_id: SecureRandom.uuid, expected_state_version: snapshot.version)
      end.to raise_error(JrcContactCenter::OperationError, 'tabulation_pending')
      expect(record.reload).to have_attributes(completed_at: nil, notes: 'SYNTHETIC overdue private draft')
    end
  end

  it 'allows an explicit native pause only after terminal call and successful ACW completion without provider confirmation' do
    completion = JrcContactCenter::QualificationManager.new(account: account, member: member)
    completion.complete!(record, { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC completed draft' })
    state = JrcContactCenter::AgentStateSnapshot.new(account_user: member)
    event = manager.transition(state: 'paused', reason_code: 'lunch', command_id: SecureRandom.uuid, expected_state_version: state.version)
    expect(record.reload.completed_at).to be_present
    expect(event.state).to eq('paused')
    expect(event.metadata.fetch('provider_confirmed')).to be(false)
    expect(member.reload.availability).to eq('lunch_break')
    expect(call.reload.status).to eq('ended')
  end
end
