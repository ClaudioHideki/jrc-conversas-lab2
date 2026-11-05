require 'rails_helper'

RSpec.describe JrcHumanAssignment::Dispatch do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false, working_hours_enabled: true, timezone: 'America/Sao_Paulo') }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:peer) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:days) { (0..6).to_h { |day| [day.to_s, []] } }
  let(:shift) { days.merge('1' => [{ 'start' => '09:00', 'end' => '12:00' }, { 'start' => '13:00', 'end' => '17:00' }]) }
  let(:options) do
    { enabled: true, mode: 'round_robin', team_ids: [team.id], max_open: 1, visibility: 'assigned_only', schedule: 'inbox' }
  end

  before do
    travel_to Time.iso8601('2026-11-09T14:00:00Z')
    [agent, peer].each do |user|
      create(:inbox_member, inbox: inbox, user: user)
      create(:team_member, team: team, user: user)
      account.account_users.find_by!(user: user).update!(availability: :online)
    end
    allow(OnlineStatusTracker).to receive(:effective_available_users).and_call_original
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id)
                                                                     .and_return(agent.id.to_s => 'online', peer.id.to_s => 'online')
  end

  after { travel_back }

  it 'skips an online agent during their scheduled lunch and keeps the same reply inbox' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                           **options.merge(agent_schedules: { agent.id.to_s => shift }))
    travel_to Time.iso8601('2026-11-09T15:30:00Z')
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    expect(described_class.new(waiting).perform).to be(true)
    expect(waiting.reload).to have_attributes(assignee_id: peer.id, inbox_id: inbox.id)
  end

  it 'preserves individual shifts when an older client omits the new field' do
    shifts = { agent.id.to_s => shift }
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options.merge(agent_schedules: shifts))
    result = JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    expect(result['agent_schedules']).to eq(shifts)
  end

  it 'rejects individual shifts belonging to another inbox or tenant' do
    outsider = create(:user, account: account, role: :agent)
    expect do
      JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                             **options.merge(agent_schedules: { outsider.id.to_s => shift }))
    end.to raise_error(ArgumentError)
    expect(JrcHumanAssignmentPolicyEvent.where(account: account)).to be_empty
  end

  it 'does not silently bypass an inbox calendar disabled after the policy was saved' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    inbox.update!(working_hours_enabled: false)
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    expect(described_class.new(waiting).perform).to be(false)
    expect(waiting.reload.assignee_id).to be_nil
    expect(waiting.auto_assignment_requested_at).to be_present
  end

  it 'rechecks working hours when the clock crosses closing time before the assignment write' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    dispatcher = described_class.new(waiting)
    allow(dispatcher).to receive(:assign_member!).and_wrap_original do |original, *args|
      travel_to(Time.iso8601('2026-11-09T21:01:00Z')) { original.call(*args) }
    end
    expect(dispatcher.perform).to be(false)
    expect(waiting.reload.assignee_id).to be_nil
  end

  it 'rechecks the individual shift before the assignment write' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                           **options.merge(agent_schedules: { agent.id.to_s => shift, peer.id.to_s => shift }))
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    dispatcher = described_class.new(waiting)
    allow(dispatcher).to receive(:assign_member!).and_wrap_original do |original, *args|
      travel_to(Time.iso8601('2026-11-09T15:30:00Z')) { original.call(*args) }
    end
    expect(dispatcher.perform).to be(false)
    expect(waiting.reload.assignee_id).to be_nil
  end

  it 'wakes a waiting FIFO queue immediately when automatic distribution is enabled again' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    account.account_users.where(user_id: [agent.id, peer.id]).each { |value| value.update!(auto_assignment_enabled: false) }
    oldest = create(:conversation, account: account, inbox: inbox, team: team)
    travel 1.minute
    newest = create(:conversation, account: account, inbox: inbox, team: team)
    clear_enqueued_jobs
    expect { member.update!(auto_assignment_enabled: true) }.to have_enqueued_job(JrcHumanAssignment::DispatchJob).with(account.id)
    JrcHumanAssignment::DispatchJob.perform_now(account.id)
    expect(oldest.reload.assignee_id).to eq(agent.id)
    expect(newest.reload.assignee_id).to be_nil
  end

  it 'recovers on the individual shift start and uses newly freed capacity without supervisor action' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin,
                                                           **options.merge(agent_schedules: { agent.id.to_s => shift }))
    account.account_users.find_by!(user: peer).update!(auto_assignment_enabled: false)
    travel_to Time.iso8601('2026-11-09T15:30:00Z')
    oldest = create(:conversation, account: account, inbox: inbox, team: team)
    travel 1.minute
    newest = create(:conversation, account: account, inbox: inbox, team: team)
    JrcHumanAssignment::DispatchJob.perform_now(account.id)
    expect(oldest.reload.assignee_id).to be_nil
    travel_to Time.iso8601('2026-11-09T16:00:00Z')
    clear_enqueued_jobs
    perform_enqueued_jobs(only: JrcHumanAssignment::DispatchJob) { JrcHumanAssignment::RecoveryJob.perform_now }
    expect(oldest.reload.assignee_id).to eq(agent.id)
    expect(newest.reload.assignee_id).to be_nil
    perform_enqueued_jobs(only: JrcHumanAssignment::DispatchJob) { oldest.update!(status: :resolved) }
    expect(newest.reload.assignee_id).to eq(agent.id)
  end

  AccountUser.availabilities.keys.excluding('online').each do |state|
    it "preserves active conversations and rejects new assignments in #{state}" do
      JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
      owned = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent)
      account.account_users.find_by!(user: peer).update!(auto_assignment_enabled: false)
      member.update!(availability: state)
      waiting = create(:conversation, account: account, inbox: inbox, team: team)
      expect(described_class.new(waiting).perform).to be(false)
      expect(waiting.reload.assignee_id).to be_nil
      expect(owned.reload.assignee_id).to eq(agent.id)
    end
  end
end
