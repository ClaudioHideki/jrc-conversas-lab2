require 'rails_helper'

RSpec.describe 'Personal inbox conversation view', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:other) { create(:user, account: account) }
  let(:own_inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:other_inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations" }

  before { create(:inbox_member, inbox: own_inbox, user: admin) }

  it 'limits personal inbox mode to actual membership before pagination, even for an administrator' do
    mine = create(:conversation, account: account, inbox: own_inbox, assignee: admin)
    shared = create(:conversation, account: account, inbox: own_inbox, assignee: other, status: :resolved)
    waiting = create(:conversation, account: account, inbox: own_inbox, status: :pending)
    foreign = create(:conversation, account: account, inbox: other_inbox, assignee: admin)
    %w[me mine_or_shared].each do |filter|
      get url, headers: admin.create_new_auth_token, params: { assignee_type: filter, inbox_scope: 'member', status: 'all' }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'payload').pluck('id')).to contain_exactly(mine.display_id, shared.display_id, waiting.display_id)
      expect(response.parsed_body.dig('data', 'meta', 'shared_scope', 'member_inbox_ids')).to eq([own_inbox.id])
    end
    get url, headers: admin.create_new_auth_token, params: { assignee_type: 'all', status: 'all' }
    expect(response.parsed_body.dig('data', 'payload').pluck('id')).to include(foreign.display_id)
    get url, headers: admin.create_new_auth_token, params: { assignee_type: 'me', status: 'all' }
    expect(response.parsed_body.dig('data', 'payload').pluck('id')).to contain_exactly(mine.display_id, foreign.display_id)
  end

  it 'does not turn an administrator without inbox membership into a member through stale assignments' do
    create(:conversation, account: account, inbox: other_inbox, assignee: admin)
    get url, headers: admin.create_new_auth_token, params: { assignee_type: 'me', inbox_scope: 'member', status: 'all' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'payload')).to be_empty
  end

  it 'intersects participating conversations with the member inbox scope instead of replacing it' do
    external = create(:conversation, account: account, inbox: other_inbox, assignee: admin)
    create(:conversation_participant, account: account, conversation: external, user: admin)
    get url, headers: admin.create_new_auth_token, params: {
      assignee_type: 'me', inbox_scope: 'member', status: 'all', conversation_type: 'participating', include_participating: true
    }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'payload')).to be_empty
    expect(response.parsed_body.dig('data', 'meta', 'all_count')).to eq(0)
  end

  it 'preserves assigned-only queues for ordinary agents even in personal inbox mode' do
    create(:inbox_member, inbox: own_inbox, user: other)
    account.update!(custom_attributes: { 'jrc_human_assignment' => { 'connections' => {
                      own_inbox.id.to_s => { 'visibility' => 'assigned_only', 'supervisor_ids' => [admin.id] }
                    } } })
    mine = create(:conversation, account: account, inbox: own_inbox, assignee: other)
    create(:conversation, account: account, inbox: own_inbox, assignee: admin)
    create(:conversation, account: account, inbox: own_inbox, status: :pending)
    %w[me mine_or_shared].each do |filter|
      get url, headers: other.create_new_auth_token, params: { assignee_type: filter, inbox_scope: 'member', status: 'all' }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('data', 'payload').pluck('id')).to eq([mine.display_id])
    end
  end
end
