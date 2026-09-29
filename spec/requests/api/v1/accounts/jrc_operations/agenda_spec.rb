require 'rails_helper'

RSpec.describe 'Agenda from native CRM and Projects', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:project) do
    p = JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Agenda delivery' }, idempotency_key: SecureRandom.uuid)
    p.project_members.create!(account: account, user: agent, role: 'viewer')
    p
  end
  let(:task) { project.tasks.create!(account: account, created_by: admin, assignee: agent, title: 'Project deadline', due_on: '2026-09-24', board_column: project.board_columns.first!) }
  let(:lead) { create(:jrc_crm_lead, account: account, owner: agent) }
  let(:activity) { create(:jrc_crm_activity, account: account, user: agent, deal: nil, lead: lead, title: 'CRM meeting', due_at: Time.utc(2026, 9, 24, 16)) }
  let(:follow_up) { JrcCrm::FollowUp.create!(account: account, user: agent, title: 'Follow-up', due_at: Time.utc(2026, 9, 24, 17)) }
  let(:url) { "/api/v1/accounts/#{account.id}/operations/agenda" }
  let(:headers) { agent.create_new_auth_token }
  let(:period) { { from: '2026-09-01', to: '2026-09-30' } }

  around { |example| travel_to(Time.utc(2026, 9, 24, 15)) { example.run } }
  before do
    account.enable_features!('jrc_crm', 'jrc_projects')
    member.update!(jrc_projects_enabled: true)
  end

  it 'combines real sources with stable identity and actual responsible person' do
    task; activity; follow_up
    get url, params: period, headers: headers
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.fetch('data')
    expect(rows.pluck('kind')).to contain_exactly('project_task', 'crm_activity', 'crm_follow_up')
    expect(rows.pluck('responsible_id').uniq).to eq([agent.id])
    expect(rows.find { |r| r['kind'] == 'project_task' }).to include('project_id' => project.id, 'task_id' => task.id, 'due_type' => 'date', 'due' => '2026-09-24')
    expect(response.parsed_body.dig('meta', 'time_zone')).to eq('America/Sao_Paulo')
    expect(response.parsed_body.dig('meta', 'unavailable_sources', 'service_desk')).to eq('native_tasks_not_available')
  end

  it 'keeps CRM and Projects working while the Service Desk source is unavailable' do
    task; activity
    %w[crm projects service_desk].each do |source|
      get url, params: period.merge(source: source), headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('data').pluck('source')).to eq(source == 'service_desk' ? [] : [source])
    end
    account.disable_features!('jrc_projects')
    get url, params: period, headers: headers
    expect(response.parsed_body.fetch('data').pluck('source')).to eq(['crm'])
  end

  it 'does not turn any R2 ticket SLA deadline into a scheduled item' do
    account.enable_features!('jrc_service_desk')
    unit = create(:jrc_sd_unit, operator_company: create(:jrc_sd_operator_company, account: account))
    create(:jrc_sd_ticket, unit: unit)
    get url, params: period.merge(source: 'service_desk'), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to be_empty
  end

  it 'revokes Project visibility immediately while preserving authorized CRM items' do
    task; activity
    member.update!(jrc_projects_enabled: false)
    get url, params: period, headers: headers
    expect(response.parsed_body.fetch('data').pluck('kind')).to eq(['crm_activity'])
  end

  it 'respects source permissions when changing the responsible filter' do
    project.project_members.create!(account: account, user: colleague, role: 'viewer')
    task.update!(assignee: colleague)
    activity.update!(user: colleague)
    get url, params: period.merge(user_id: colleague.id), headers: headers
    expect(response.parsed_body.fetch('data').pluck('kind')).to eq(['project_task'])
    get url, params: period.merge(user_id: 'all'), headers: admin.create_new_auth_token
    expect(response.parsed_body.fetch('data').pluck('responsible_id').uniq).to eq([colleague.id])
    foreign = create(:user, account: create(:account))
    get url, params: period.merge(user_id: foreign.id), headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'distinguishes completed, canceled, overdue and current date-only tasks' do
    task.update!(due_on: '2026-09-23', status: 'canceled', board_column: nil)
    follow_up.update!(completed_at: Time.current, is_completed: true)
    activity.update!(due_at: Time.current - 1.hour)
    { 'canceled' => ['project_task'], 'completed' => ['crm_follow_up'], 'overdue' => ['crm_activity'] }.each do |view, kinds|
      get url, params: period.merge(view: view), headers: headers
      expect(response.parsed_body.fetch('data').pluck('kind')).to eq(kinds)
    end
  end

  it 'uses a half-open local-day range across DST without inventing times for project dates' do
    account.update!(reporting_timezone: 'America/New_York')
    activity.update!(due_at: Time.utc(2026, 11, 1, 4))
    follow_up.update!(due_at: Time.utc(2026, 11, 2, 5))
    get url, params: { from: '2026-11-01', to: '2026-11-01', source: 'crm' }, headers: headers
    expect(response.parsed_body.fetch('data').pluck('kind')).to eq(['crm_activity'])
    expect(response.parsed_body.dig('data', 0, 'due')).to eq('2026-11-01T00:00:00-04:00')
  end

  it 'rejects malformed and unbounded date ranges' do
    [{ from: 'yesterday' }, { from: '2026-09-30', to: '2026-09-01' }, { from: '2024-01-01', to: '2026-09-01' }].each do |bad|
      get url, params: bad, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
