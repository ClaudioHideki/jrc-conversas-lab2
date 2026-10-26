require 'rails_helper'

RSpec.describe 'Automatic assignment administration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'lets an administrator change only this account flag with an atomic audit and preserves configured availability' do
    foreign = create(:account)
    foreign_member = create(:account_user, account: foreign, user: agent)
    expect do
      patch "/api/v1/accounts/#{account.id}/agents/#{agent.id}",
            params: { agent: { auto_assignment_enabled: false } }, headers: admin.create_new_auth_token, as: :json
    end.to change { Audited::Audit.where(auditable: member, comment: 'auto_assignment_configuration_v1').count }.by(1)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['auto_assignment_enabled']).to be(false)
    expect(response.parsed_body['availability']).to eq('online')
    expect(member.reload).not_to be_auto_assignment_enabled
    expect(foreign_member.reload).to be_auto_assignment_enabled
    expect(inbox.members).to include(agent)
  end

  it 'rejects a non-administrator changing their own automatic assignment flag' do
    patch "/api/v1/accounts/#{account.id}/agents/#{agent.id}",
          params: { agent: { auto_assignment_enabled: false } }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(member.reload).to be_auto_assignment_enabled
  end

  it 'preserves authorized manual assignment when automatic assignment is disabled' do
    member.update!(auto_assignment_enabled: false)
    conversation = create(:conversation, account: account, inbox: inbox)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/assignments",
         params: { assignee_id: agent.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(conversation.reload.assignee_id).to eq(agent.id)
  end

  it 'keeps an individually excluded agent in the native manual assignment dropdown' do
    member.update!(auto_assignment_enabled: false, availability: :offline)

    get "/api/v1/accounts/#{account.id}/assignable_agents", params: { inbox_ids: [inbox.id] }, headers: admin.create_new_auth_token

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['payload'].map { |row| row['id'] }).to include(agent.id)
  end

  it 'reports a missing policy to administrators without creating a policy' do
    account.enable_features!('assignment_v2')
    inbox.update!(enable_auto_assignment: true)
    expect do
      get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/assignment_diagnostics", headers: admin.create_new_auth_token
    end.not_to change(AssignmentPolicy, :count)

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['reason']).to eq('policy_missing')
    expect(response.parsed_body.keys).not_to include('messages', 'contacts', 'users')
  end

  it 'rejects diagnostics for non-administrators' do
    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/assignment_diagnostics", headers: agent.create_new_auth_token

    expect(response).to have_http_status(:unauthorized)
  end

  it 'isolates inbox and conversation diagnostics by account and inbox' do
    foreign_inbox = create(:inbox)
    foreign_conversation = create(:conversation, inbox: foreign_inbox, account: foreign_inbox.account)
    get "/api/v1/accounts/#{account.id}/inboxes/#{foreign_inbox.id}/assignment_diagnostics", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)

    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/assignment_diagnostics",
        params: { conversation_id: foreign_conversation.id }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
