require 'rails_helper'

RSpec.describe 'Exclusive inbox HTTP access', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:peer) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }

  before do
    [agent, peer].each { |user| create(:inbox_member, inbox: inbox, user: user) }
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'connections' => {
                      inbox.id.to_s => { 'visibility' => 'assigned_only', 'supervisor_ids' => [] }
                    } } })
  end

  it 'denies the direct conversation and its attachment list to a peer' do
    ['', '/attachments'].each do |suffix|
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}#{suffix}", headers: peer.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    end
  end

  it 'keeps the owner authorized without exposing the same conversation in contact history to a peer' do
    get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    get "/api/v1/accounts/#{account.id}/contacts/#{conversation.contact_id}/conversations", headers: peer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to be_empty
  end

  it 'does not reuse another agents conversation or send a message through the create endpoint' do
    inbox.update!(lock_to_single_conversation: true)
    existing = conversation
    input = { inbox_id: inbox.id, contact_id: existing.contact_id, source_id: existing.contact_inbox.source_id,
              message: { content: 'Synthetic unauthorized send', message_type: 'outgoing' } }
    expect do
      post "/api/v1/accounts/#{account.id}/conversations", headers: peer.create_new_auth_token, params: input, as: :json
    end.not_to(change { existing.messages.count })
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not immediately self-assign a paused agent reopening through the dashboard endpoint' do
    owned = conversation
    team = create(:team, account: account, allow_auto_assign: true)
    create(:team_member, team: team, user: agent)
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'connections' => {
                      inbox.id.to_s => { 'enabled' => true, 'visibility' => 'assigned_only', 'supervisor_ids' => [],
                                         'team_ids' => [team.id], 'max_open' => 1, 'mode' => 'round_robin' }
                    } } })
    owned.update!(team: team, status: :resolved)
    account.account_users.find_by!(user: agent).update!(availability: :lunch_break)
    post "/api/v1/accounts/#{account.id}/conversations/#{owned.display_id}/toggle_status",
         headers: agent.create_new_auth_token, params: { status: 'open' }, as: :json
    expect(response).to have_http_status(:ok)
    expect(owned.reload.assignee_id).to be_nil
    expect(owned.auto_assignment_requested_at).to be_present
  end
end
