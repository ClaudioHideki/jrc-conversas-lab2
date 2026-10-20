require 'rails_helper'

RSpec.describe 'Human assignment across inboxes', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency

  it 'serializes simultaneous inbox arrivals without exceeding the agent account limit' do
    account = create(:account, custom_attributes: { 'jrc_human_assignment' => { 'enabled' => true, 'max_open' => 1 } })
    team = create(:team, account: account, allow_auto_assign: true)
    agents = create_list(:user, 2, account: account, role: :agent)
    agents.each { |agent| create(:team_member, team: team, user: agent) }
    ids = Array.new(3) do
      inbox = create(:inbox, account: account, enable_auto_assignment: false)
      agents.each { |agent| create(:inbox_member, inbox: inbox, user: agent) }
      conversation = create(:conversation, account: account, inbox: inbox, status: :open)
      conversation.update_columns(team_id: team.id, assignee_id: nil)
      conversation.id
    end
    JrcHumanAssignment::Policy.update!(account, enabled: true, max_open: 1, inbox_ids: account.inboxes.ids)
    allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id)
      .and_return(agents.to_h { |agent| [agent.id.to_s, 'online'] })

    results = concurrently(ids.map { |id| -> { JrcHumanAssignment::Dispatch.new(Conversation.find(id)).perform } })

    expect(results.count(true)).to eq(2)
    expect(results.count(false)).to eq(1)
    expect(account.conversations.where.not(assignee_id: nil).group(:assignee_id).count.values).to eq([1, 1])
    expect(account.conversations.where(assignee_id: nil).count).to eq(1)
    expect(account.conversations.distinct.count(:inbox_id)).to eq(3)
  end
end
