require 'rails_helper'

RSpec.describe JrcHumanAssignment::DispatchJob do
  it 'processes oldest queue entry first even when its conversation was created later' do
    account = create(:account)
    inbox = create(:inbox, account: account, enable_auto_assignment: false)
    team = create(:team, account: account, allow_auto_assign: true)
    first = create(:conversation, account: account, inbox: inbox, team: team)
    second = create(:conversation, account: account, inbox: inbox, team: team)
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'connections' => {
                      inbox.id.to_s => { 'enabled' => true, 'mode' => 'round_robin', 'team_ids' => [team.id], 'max_open' => 1,
                                         'fallback' => 'waiting' }
                    } } })
    first.update!(assignee_id: nil, auto_assignment_requested_at: 1.hour.ago)
    second.update!(assignee_id: nil, auto_assignment_requested_at: 2.hours.ago)
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return({})
    described_class.perform_now(account.id)
    events = JrcBrokerConnectionEvent.where(account: account, event_type: 'DISTRIBUTION_FALLBACK').order(:id)
    expect(events.map { |event| event.metadata['conversation_id'] }).to eq([second.id, first.id])
  end
end
