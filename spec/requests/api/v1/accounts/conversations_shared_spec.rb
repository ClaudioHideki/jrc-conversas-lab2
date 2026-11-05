require 'rails_helper'

RSpec.describe 'Shared inbox conversation contract', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:other_agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations" }

  before { create(:inbox_member, inbox: inbox, user: agent) }

  it 'returns additive scope metadata, shared count and authorized rows without relabeling mine_count' do
    mine = create(:conversation, account: account, inbox: inbox, assignee: agent)
    shared = create(:conversation, account: account, inbox: inbox, assignee: other_agent)
    get url, headers: agent.create_new_auth_token, params: { assignee_type: 'mine_or_shared' }
    expect(response).to have_http_status(:ok)
    body = response.parsed_body.fetch('data')
    expect(body.fetch('payload').pluck('id')).to contain_exactly(mine.display_id, shared.display_id)
    expect(body.fetch('meta')).to include('mine_count' => 1, 'mine_or_shared_count' => 2,
                                        'shared_scope' => { 'enabled' => true, 'inbox_ids' => [inbox.id] })
    get "#{url}/meta", headers: agent.create_new_auth_token, params: { assignee_type: 'mine_or_shared' }
    expect(response.parsed_body.fetch('meta').fetch('shared_scope')).to eq('enabled' => true, 'inbox_ids' => [inbox.id])
    get url, headers: agent.create_new_auth_token, params: { assignee_type: 'me' }
    expect(response.parsed_body.dig('data', 'payload').pluck('id')).to eq([mine.display_id])
  end

  it 'does not accept inbox ids or a shared capability supplied by the client' do
    inaccessible = create(:inbox, account: account, enable_auto_assignment: false)
    create(:conversation, account: account, inbox: inaccessible, assignee: other_agent)
    get url, headers: agent.create_new_auth_token,
             params: { assignee_type: 'mine_or_shared', inbox_id: inaccessible.id, shared_scope: { enabled: true, inbox_ids: [inaccessible.id] } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'payload')).to be_empty
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/conversations", headers: agent.create_new_auth_token, params: { assignee_type: 'mine_or_shared' }
    expect(response).to have_http_status(:unauthorized)
  end
end
