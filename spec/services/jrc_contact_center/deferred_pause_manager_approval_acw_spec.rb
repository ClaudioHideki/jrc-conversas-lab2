require 'rails_helper'

RSpec.describe JrcContactCenter::DeferredPauseManager, 'approval after call and ACW', :approval_core do
  include_context 'with all-scope native pause approval'
  include_context 'with a native pending voice ACW for deferred pause'

  it 'does not override the actual pending qualification merely because all companies approved' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    expect(apply_pause(row).state).to eq('pending')
    expect(JrcContactCenter::Qualification.pending.exists?(id: pending_pause_qualification.id)).to be(true)
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.fetch(:state)).to eq('acw')
  end

  it 'consumes the approved native pause once after actual ACW completion without a provider command' do
    publish_all_pause_policies
    row = create_reviewed_pause
    approve_pause_requests
    JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(
      pending_pause_qualification, { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC approved pause after native ACW' }
    )
    expect(row.reload.state).to eq('applied')
    event = JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused').sole
    expect(event.metadata.fetch('provider_confirmed')).to be(false)
    expect(event.metadata.fetch('pause_approval_scope_ids').size).to eq(2)
    expect(JrcContactCenter::AgentStateSnapshot.new(account_user: member).call.fetch(:state)).to eq('paused')
  end
end
