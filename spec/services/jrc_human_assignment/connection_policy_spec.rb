require 'rails_helper'

RSpec.describe 'Per-connection human distribution' do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:team) { create(:team, account: account, allow_auto_assign: true) }
  let(:second_team) { create(:team, account: account, allow_auto_assign: true) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:input) { { enabled: true, mode: 'priority', team_ids: [team.id, second_team.id], max_open: 2 } }

  it 'configures one inbox without enabling a second inbox or moving existing conversations' do
    other_inbox = create(:inbox, account: account, enable_auto_assignment: false)
    conversation = create(:conversation, account: account, inbox: inbox, assignee: admin)
    expect { JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input) }
      .to change(JrcHumanAssignmentPolicyEvent, :count).by(1)
    expect(JrcHumanAssignment::Policy.enabled_for?(account.reload, inbox.id)).to be(true)
    expect(JrcHumanAssignment::Policy.enabled_for?(account, other_inbox.id)).to be(false)
    expect(conversation.reload.assignee_id).to eq(admin.id)
    expect(JrcHumanAssignment::Policy.connection_for(account, inbox.id)).to include('team_ids' => input[:team_ids])
  end

  it 'rejects a foreign team atomically, including the audit record' do
    foreign = create(:team, account: create(:account))
    expect { JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input.merge(team_ids: [foreign.id])) }
      .to raise_error(ArgumentError)
    expect(account.reload.custom_attributes['jrc_human_assignment']).to be_nil
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id)).to be_empty
  end

  it 'rechecks administrator membership instead of trusting an actor from another account' do
    foreign_admin = create(:user, account: create(:account), role: :administrator)
    expect { JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: foreign_admin, **input) }.to raise_error(ArgumentError)
  end

  it 'uses eligible fallback teams and preserves the source inbox and existing bot routing' do
    create(:inbox_member, inbox: inbox, user: other_agent)
    create(:team_member, team: second_team, user: other_agent)
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return(other_agent.id.to_s => 'online')
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input)
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::DispatchJob.perform_now(account.id)
    expect(conversation.reload).to have_attributes(inbox_id: inbox.id, team_id: second_team.id, assignee_id: other_agent.id)
    retained = create(:conversation, account: account, inbox: inbox, team: team, status: :open)
    retained.update_columns(assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::Dispatch.new(retained).perform
    expect(retained.reload.team_id).to eq(team.id)
    expect(retained.assignee_id).to be_nil
  end

  it 'routes direct mode to a team without automatically assigning an agent' do
    create(:inbox_member, inbox: inbox, user: agent)
    create(:team_member, team: team, user: agent)
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id).and_return(agent.id.to_s => 'online')
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input.merge(mode: 'direct', team_ids: [team.id]))
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::DispatchJob.perform_now(account.id)
    expect(conversation.reload.team_id).to eq(team.id)
    expect(conversation.assignee_id).to be_nil
  end

  it 'does not consume capacity or route an unrequested historical conversation' do
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input)
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: nil)
    JrcHumanAssignment::DispatchJob.perform_now(account.id)
    expect(conversation.reload.team_id).to be_nil
  end
  it 'rotates eligible teams and respects aggregate capacity across inboxes' do
    [[team, agent], [second_team, other_agent]].each do |selected_team, selected_agent|
      create(:inbox_member, inbox: inbox, user: selected_agent)
      create(:team_member, team: selected_team, user: selected_agent)
    end
    allow(OnlineStatusTracker).to receive(:effective_available_users).with(account.id)
      .and_return(agent.id.to_s => 'online', other_agent.id.to_s => 'online')
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input.merge(mode: 'round_robin', max_open: 1))
    first = create(:conversation, account: account, inbox: inbox, status: :open)
    first.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::Dispatch.new(first).perform
    second = create(:conversation, account: account, inbox: inbox, status: :open)
    second.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::Dispatch.new(second).perform
    expect([first.reload.team_id, second.reload.team_id]).to eq([team.id, second_team.id])
    expect([first.assignee_id, second.assignee_id]).to eq([agent.id, other_agent.id])
    third = create(:conversation, account: account, inbox: inbox, status: :open)
    third.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: Time.current)
    JrcHumanAssignment::Dispatch.new(third).perform
    expect(third.reload.assignee_id).to be_nil
  end

  it 'applies a changed policy only to requests received after it was saved' do
    conversation = create(:conversation, account: account, inbox: inbox, status: :open)
    conversation.update_columns(team_id: nil, assignee_id: nil, auto_assignment_requested_at: 1.minute.ago)
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input)
    JrcHumanAssignment::Dispatch.new(conversation).perform
    expect(conversation.reload.team_id).to be_nil
  end

  it 'preserves other connection policies when a stale account object saves' do
    stale = Account.find(account.id)
    second = create(:inbox, account: account, enable_auto_assignment: false)
    JrcHumanAssignment::Policy.update_connection!(account, inbox: inbox, actor: admin, **input)
    JrcHumanAssignment::Policy.update_connection!(stale, inbox: second, actor: admin, **input)
    expect(JrcHumanAssignment::Policy.enabled_inbox_ids(account.reload)).to contain_exactly(inbox.id, second.id)
    expect(JrcHumanAssignmentPolicyEvent.where(account_id: account.id).count).to eq(2)
  end

end
