require 'rails_helper'

RSpec.describe JrcCustomers::Customer360 do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:company) { account.master_companies.create!(name: 'Synthetic customer') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:context) do
    described_class.new(account: account, user: user,
                        account_user: account.account_users.find_by!(user_id: user.id), company: company)
  end

  before { account.enable_features!('jrc_customer_master') }

  it 'projects real authorized relations with a limited sample and an explicit complete count' do
    conversations = Array.new(12) { create(:conversation, account: account, contact: contact) }
    create(:message, account: account, conversation: conversations.first, content: 'PRIVATE_NOTE_CANARY', private: true)
    result = context.relationship_map
    group = result.fetch(:groups).find { |item| item[:kind] == 'conversations' }

    expect(group).to include(total: 12, has_more: true)
    expect(group.fetch(:nodes).size).to eq(10)
    expect(group.fetch(:nodes).map { |node| node[:id] }).to match_array(conversations.last(10).map(&:id))
    expect(result.fetch(:edges)).to include(source: "company:#{company.id}", target: "conversations:#{conversations.last.id}",
                                            relation: 'customer_context')
    expect(result.to_json).not_to include('PRIVATE_NOTE_CANARY', 'phone_number', 'email', 'content_attributes')
  end

  it 'does not expose unavailable CRM modules as empty groups' do
    result = context.relationship_map
    expect(result.fetch(:groups).map { |group| group[:kind] }).not_to include('leads', 'deals', 'activities', 'proposals', 'contracts')
    expect(result.fetch(:root)).to eq(key: "company:#{company.id}")
    expect(result.fetch(:sample_limit)).to eq(10)
  end

  it 'excludes conversations belonging to another customer or account' do
    visible = create(:conversation, account: account, contact: contact)
    unrelated = create(:conversation, account: account)
    foreign = create(:conversation)
    result = context.relationship_map
    nodes = result.fetch(:groups).find { |group| group[:kind] == 'conversations' }.fetch(:nodes)
    expect(nodes.map { |node| node[:id] }).to eq([visible.id])
    expect(nodes.map { |node| node[:id] }).not_to include(unrelated.id, foreign.id)
  end

  it 'omits an inbox that the current agent is not authorized to see' do
    agent = create(:user, account: account, role: :agent)
    inbox = create(:channel_api, account: account).inbox
    create(:conversation, account: account, inbox: inbox, contact: contact)
    restricted = described_class.new(account: account, user: agent,
                                     account_user: account.account_users.find_by!(user_id: agent.id), company: company)
    group = restricted.relationship_map.fetch(:groups).find { |item| item[:kind] == 'conversations' }
    expect(group).to include(total: 0, has_more: false, nodes: [])
  end

  it 'includes real zero counts for available CRM sources' do
    account.enable_features!('jrc_crm')
    group = context.relationship_map.fetch(:groups).find { |item| item[:kind] == 'deals' }
    expect(group).to include(total: 0, has_more: false, nodes: [])
  end

  it 'omits project tasks when the current custom role cannot view tasks' do
    membership = account.account_users.find_by!(user_id: user.id)
    allow(membership).to receive_messages(custom_role_id: 1, custom_role: instance_double(CustomRole, permissions: ['jrc_projects_project_view']))
    visibility = JrcCustomers::Visibility.new(account: account, user: user, account_user: membership)
    context.instance_variable_set(:@visibility, visibility)
    allow(context).to receive(:sources).and_return('project_tasks' => JrcProjects::Task.none)

    expect(context.relationship_map.fetch(:groups)).to be_empty
  end

  it 'does not duplicate a visible resource when its authorized scope contains multiple joined rows' do
    conversation = create(:conversation, account: account, contact: contact)
    2.times { create(:message, account: account, conversation: conversation, content: 'Synthetic', private: false) }
    allow(context).to receive(:sources).and_return('conversations' => context.conversations.joins(:messages))
    group = context.relationship_map.fetch(:groups).first
    expect(group).to include(total: 1, has_more: false)
    expect(group.fetch(:nodes).map { |node| node[:id] }).to eq([conversation.id])
  end
end
