require 'rails_helper'

RSpec.describe JrcHumanAssignment::Dispatch do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:peer) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:options) do
    { enabled: true, mode: 'round_robin', team_ids: [team.id], max_open: 10,
      visibility: 'assigned_only', supervisor_ids: [], agent_limits: { agent.id.to_s => 20, peer.id.to_s => 5 } }
  end

  before do
    [agent, peer].each do |user|
      create(:inbox_member, inbox: inbox, user: user)
      create(:team_member, team: team, user: user)
      account.account_users.find_by!(user: user).update!(availability: :online)
    end
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id)
                                                                     .and_return(agent.id.to_s => 'online', peer.id.to_s => 'online')
  end

  it 'accepts an exclusive policy with individual limits and selects 30 percent before 80 percent' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    create_list(:conversation, 6, account: account, inbox: inbox, assignee: agent)
    create_list(:conversation, 4, account: account, inbox: inbox, assignee: peer)
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    expect(described_class.new(waiting).perform).to be(true)
    expect(waiting.reload.assignee_id).to eq(agent.id)
    decision = JrcBrokerConnectionEvent.where(account: account, event_type: 'DISTRIBUTION_ASSIGNED').last
    expect(decision&.metadata).to include('conversation_id' => waiting.id, 'agent_id' => agent.id, 'active_count' => 7, 'capacity_limit' => 20)
  end

  it 'rejects bypassing presence or capacity in exclusive mode' do
    [:respect_availability, :capacity_enabled].each do |key|
      expect { JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options.merge(key => false)) }
        .to raise_error(ArgumentError)
    end
  end

  it 'invalidates previously built filtered counts when central visibility is enabled' do
    account.enable_features!('unread_count_for_filters')
    owned = create_unread_conversation(account: account, inbox: inbox, assignee: peer)
    create(:mention, account: account, conversation: owned, user: agent)
    counter = Conversations::UnreadCounts::FilteredCounter
    expect(counter.new(account: account, user: agent).perform[:mentions_count]).to eq(1)
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    expect(counter.new(account: account, user: agent).perform[:mentions_count]).to eq(0)
  end

  it 'never serves a stale filtered count after ownership is transferred' do
    account.enable_features!('unread_count_for_filters')
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    owned = create_unread_conversation(account: account, inbox: inbox, assignee: agent)
    create(:mention, account: account, conversation: owned, user: agent)
    counter = Conversations::UnreadCounts::FilteredCounter
    expect(counter.new(account: account, user: agent).perform[:mentions_count]).to eq(1)
    owned.update!(assignee: peer)
    expect(counter.new(account: account, user: agent).perform[:mentions_count]).to eq(0)
  end

  it 'keeps already admitted waiting requests eligible after a policy edit' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    requested_at = waiting.auto_assignment_requested_at
    travel 1.minute do
      JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options.merge(max_open: 4))
      expect(waiting.reload.auto_assignment_requested_at).to eq(requested_at)
      expect(described_class.new(waiting).perform).to be(true)
    end
  end

  it 'uses round robin when 6 of 10 and 3 of 5 have equal occupancy' do
    config = options.merge(agent_limits: { agent.id.to_s => 10, peer.id.to_s => 5 })
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **config)
    JrcHumanAssignment::Policy.record_cursor!(account, inbox.id, agent_id: agent.id, team_id: team.id)
    create_list(:conversation, 6, account: account, inbox: inbox, assignee: agent)
    create_list(:conversation, 3, account: account, inbox: inbox, assignee: peer)
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    expect(described_class.new(waiting).perform).to be(true)
    expect(waiting.reload.assignee_id).to eq(peer.id)
  end

  it 'does not count another inbox against the individual central-inbox limit' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    other = create(:inbox, account: account, enable_auto_assignment: false)
    create_list(:conversation, 3, account: account, inbox: other, assignee: agent)
    create(:conversation, account: account, inbox: inbox, assignee: peer)
    waiting = create(:conversation, account: account, inbox: inbox, team: team)
    expect(described_class.new(waiting).perform).to be(true)
    expect(waiting.reload.assignee_id).to eq(agent.id)
  end

  it 'rejects supervisors and capacity entries outside the inbox' do
    outsider = create(:user, account: account, role: :agent)
    expect { JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options.merge(supervisor_ids: [outsider.id])) }
      .to raise_error(ArgumentError)
    expect do
      JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options.merge(agent_limits: { outsider.id.to_s => 3 }))
    end
      .to raise_error(ArgumentError)
  end

  it 'wakes the queue on availability return without transferring existing assignments' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    owned = create(:conversation, account: account, inbox: inbox, assignee: agent)
    member = account.account_users.find_by!(user: agent)
    member.update!(availability: :lunch_break)
    expect(owned.reload.assignee_id).to eq(agent.id)
    expect { member.update!(availability: :online) }.to have_enqueued_job(JrcHumanAssignment::DispatchJob).with(account.id)
  end

  it 'redistributes a reopened conversation when its previous agent is paused' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    owned = create(:conversation, account: account, inbox: inbox, team: team, assignee: agent, status: :resolved)
    account.account_users.find_by!(user: agent).update!(availability: :lunch_break)
    owned.update!(status: :open)
    described_class.new(owned).perform
    expect(owned.reload.assignee_id).to eq(peer.id)
  end

  it 'prefers the previous agent on reopen when they still have capacity' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    owned = create(:conversation, account: account, inbox: inbox, team: team, assignee: peer, status: :resolved)
    owned.update!(status: :open)
    described_class.new(owned).perform
    expect(owned.reload.assignee_id).to eq(peer.id)
  end

  it 'wakes the persisted queue when a live session returns after its presence expired' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    Redis::Alfred.zremrangebyscore(OnlineStatusTracker.presence_key(account.id, 'User'), '-inf', '+inf')
    expect { OnlineStatusTracker.update_presence(account.id, 'User', agent.id) }
      .to have_enqueued_job(JrcHumanAssignment::DispatchJob).with(account.id)
  end

  it 'does not let a native URA directly assign an unavailable agent' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **options)
    owned = create(:conversation, account: account, inbox: inbox, team: team)
    flow = JrcFlow.create!(account: account, name: 'Synthetic central URA',
                           graph: { 'nodes' => [{ 'id' => 'start', 'type' => 'start', 'label' => 'Start',
                                                  'position' => { 'x' => 0, 'y' => 0 }, 'data' => {} }], 'edges' => [] },
                           settings: { 'inbox_ids' => [], 'days' => [] })
    run = flow.runs.create!(account: account, conversation: owned, event_key: SecureRandom.uuid,
                            graph: flow.graph, settings: {}, status: 'running')
    account.account_users.find_by!(user: agent).update!(availability: :lunch_break)
    JrcFlows::Actions.new(run).execute('assign', 'team_id' => team.id, 'agent_id' => agent.id)
    expect(owned.reload.assignee_id).to be_nil
    expect(described_class.new(owned).perform).to be(false)
    expect { run.update!(status: 'completed') }.to have_enqueued_job(JrcHumanAssignment::DispatchJob).with(account.id)
    expect(described_class.new(owned).perform).to be(true)
    expect(owned.reload.assignee_id).to eq(peer.id)
  end
end
