require 'rails_helper'

RSpec.describe 'Project delivery portfolio and serializers', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: admin,
      attributes: { name: 'Visible delivery', due_on: (Date.current + 7).iso8601 }, idempotency_key: SecureRandom.uuid)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/projects" }
  let(:task) do
    project.tasks.create!(account: account, created_by: admin, title: 'Delivery task', status: 'backlog',
                         board_column: project.board_columns.find_by!(status_key: 'backlog'))
  end

  before do
    account.enable_features!('jrc_projects')
    account.account_users.find_by!(user: agent).update!(jrc_projects_enabled: true)
  end

  it 'aggregates deliveries and filter options only for projects visible to the requesting agent' do
    project.project_members.create!(account: account, user: agent, role: 'viewer')
    project.update!(contact: create(:contact, account: account))
    hidden = JrcProjects::Projects::Create.call(account: account, actor: admin,
      attributes: { name: 'Private delivery', due_on: (Date.current + 7).iso8601 }, idempotency_key: SecureRandom.uuid)
    hidden.update!(visibility: 'private', contact: create(:contact, account: account))
    task
    get "#{base}/portfolio", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    data = response.parsed_body.fetch('data')
    expect(data).to include('total' => 1, 'tasks_total' => 1)
    expect(data.fetch('deliveries').sum { |row| row.fetch('planned') }).to eq(1)
    expect(data.dig('filter_options', 'contacts').pluck('id')).to eq([project.contact_id])
  end

  it 'groups completions in the account request timezone without double-counting month boundaries' do
    project.update!(status: 'completed', completed_at: Time.utc(2026, 10, 1, 1), due_on: Date.new(2026, 10, 10))
    travel_to Time.utc(2026, 10, 22, 12) do
      Time.use_zone('America/Sao_Paulo') do
        get "#{base}/portfolio", headers: headers
        expect(response).to have_http_status(:ok)
        months = response.parsed_body.dig('data', 'deliveries').index_by { |row| row.fetch('month') }
        expect(months.fetch('2026-09').fetch('completed')).to eq(1)
        expect(months.fetch('2026-10').fetch('planned')).to eq(1)
      end
    end
  end

  it 'searches contact, owner and project key and respects combined filters and tenant isolation' do
    project.update!(contact: create(:contact, account: account, name: 'Delivery client'))
    [project.key, admin.name, 'Delivery client'].each do |query|
      get "#{base}/projects", params: { q: query, owner_id: admin.id, contact_id: project.contact_id }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').pluck('id')).to eq([project.id])
    end
    outsider = create(:user, account: create(:account), role: :administrator)
    get "#{base}/projects/#{project.id}", headers: outsider.create_new_auth_token
    expect(response.status).to be_in([401, 403, 404])
  end

  it 'returns real checklist, comment and attachment counters on cards and task endpoints' do
    task.checklist_items.create!(account: account, text: 'Done', completed: true)
    task.checklist_items.create!(account: account, text: 'Pending', completed: false)
    task.task_comments.create!(account: account, user: admin, body: 'Internal comment')
    task.attachments.attach(io: StringIO.new('local test'), filename: 'delivery.txt', content_type: 'text/plain')
    get "#{base}/projects/#{project.id}/tasks", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').first).to include(
      'checklist_total' => 2, 'checklist_completed' => 1, 'comments_count' => 1, 'attachments_count' => 1)
    get "#{base}/projects", headers: headers
    expect(response.parsed_body.fetch('data').first).to include('comments_count' => 1, 'attachments_count' => 1)
  end

  it 'keeps the financial projection hidden from viewers and reports unconfigured budgets honestly to owners' do
    project.project_members.create!(account: account, user: agent, role: 'viewer')
    get "#{base}/projects/#{project.id}", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).not_to have_key('budget')
    get "#{base}/projects/#{project.id}", headers: headers
    expect(response.parsed_body.dig('data', 'budget')).to include('configured' => false, 'planned_cents' => 0)
  end
end
