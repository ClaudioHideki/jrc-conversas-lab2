require 'rails_helper'

# Real Rails/PostgreSQL/ActiveStorage tests. These are not executed by the Node
# structural suite; use a dedicated test database with the existing migrations.
RSpec.describe 'JRC Projects planning checkpoint 3C', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token.merge('X-Request-Id' => 'planning-3c-request') }
  let(:member_headers) { member.create_new_auth_token }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Planning delivery' }, idempotency_key: SecureRandom.uuid)
  end
  let(:other_project) do
    JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Other delivery' }, idempotency_key: SecureRandom.uuid)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}" }
  let(:backlog) { project.board_columns.find_by!(status_key: 'backlog') }
  let(:task) do
    project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Delivery task', estimated_minutes: 120)
  end
  let(:milestone) { project.milestones.create!(account: account, name: 'Acceptance', due_on: Date.current + 7) }

  before do
    account.account_users.find_by!(user: member).update!(jrc_projects_enabled: true)
    account.enable_features!('jrc_projects')
    project.project_members.create!(account: account, user: member, role: 'member')
  end

  it 'creates, edits, completes and removes a milestone with correlation and no duplicate completion event' do
    phase = project.phases.create!(account: account, name: 'Delivery phase')
    post "#{base}/milestones", params: { record: { name: 'First delivery', due_on: '2026-10-10', status: 'open', phase_id: phase.id,
                                                description: 'Ignored: no such field', owner_id: member.id, progress: 50 } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    record = JrcProjects::Milestone.find(response.parsed_body.dig('data', 'id'))
    expect(record).to have_attributes(name: 'First delivery', phase_id: phase.id)
    expect(record.attributes.keys).not_to include('description', 'owner_id', 'progress', 'task_id')
    patch "#{base}/milestones/#{record.id}", params: { record: { name: 'Revised delivery', due_on: '2026-10-12' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    2.times do
      patch "#{base}/milestones/#{record.id}", params: { record: { status: 'completed' } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(record.reload).to have_attributes(name: 'Revised delivery', status: 'completed', due_on: Date.new(2026, 10, 12))
    delete "#{base}/milestones/#{record.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    events = JrcProjects::AuditEvent.where(account: account, auditable_type: 'JrcProjects::Milestone', auditable_id: record.id)
    expect(events.pluck(:action)).to contain_exactly('projects.milestone.created', 'projects.milestone.updated', 'projects.milestone.completed', 'projects.milestone.deleted')
    expect(events.pluck(:correlation_id).uniq).to eq(['planning-3c-request'])
    get base, headers: headers
    expect(response.parsed_body.dig('data', 'recent_activity').map { |event| event['action'] }).to include('projects.milestone.deleted')
  end

  it 'rejects phases and milestone ids from another project and account' do
    foreign_account = create(:account)
    foreign_account.enable_features!('jrc_projects')
    foreign_user = create(:user, account: foreign_account, role: :administrator)
    foreign_project = JrcProjects::Projects::Create.call(account: foreign_account, actor: foreign_user,
      attributes: { name: 'Foreign project' }, idempotency_key: SecureRandom.uuid)
    [other_project, foreign_project].each do |outside|
      phase = outside.phases.create!(account: outside.account, name: 'Foreign phase')
      post "#{base}/milestones", params: { record: { name: 'Invalid phase', phase_id: phase.id } }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
      expect(project.milestones.new(account: account, name: 'Invalid model phase', phase: phase)).not_to be_valid
    end
    other = other_project.milestones.create!(account: account, name: 'Other milestone')
    patch "#{base}/milestones/#{other.id}", params: { record: { status: 'completed' } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(other.reload.status).to eq('open')
  end

  it 'adds, updates and removes a participant and refreshes task assignee options through the project' do
    user = create(:user, account: account, role: :agent)
    post "#{base}/members", params: { record: { user_id: user.id, role: 'member', allocation_percent: 50 } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    membership = JrcProjects::ProjectMember.find(response.parsed_body.dig('data', 'id'))
    patch "#{base}/members/#{membership.id}", params: { record: { role: 'manager', allocation_percent: 75 } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(membership.reload).to have_attributes(role: 'manager', allocation_percent: 75)
    get base, headers: headers
    expect(response.parsed_body.dig('data', 'members').map { |entry| entry['user_id'] }).to include(user.id)
    delete "#{base}/members/#{membership.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    get base, headers: headers
    expect(response.parsed_body.dig('data', 'members').map { |entry| entry['user_id'] }).not_to include(user.id)
    events = JrcProjects::AuditEvent.where(account: account, auditable_type: 'JrcProjects::ProjectMember', auditable_id: membership.id)
    expect(events.pluck(:action)).to contain_exactly('projects.member.created', 'projects.member.updated', 'projects.member.deleted')
    expect(events.pluck(:correlation_id).uniq).to eq(['planning-3c-request'])
  end

  it 'protects the owner and requires reassignment before removing or replacing an assigned participant' do
    owner = project.project_members.find_by!(user: admin)
    patch "#{base}/members/#{owner.id}", params: { record: { role: 'viewer' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    delete "#{base}/members/#{owner.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(owner.reload.role).to eq('owner')
    membership = project.project_members.find_by!(user: member)
    task.update!(assignee: member)
    delete "#{base}/members/#{membership.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    replacement = create(:user, account: account, role: :agent)
    patch "#{base}/members/#{membership.id}", params: { record: { user_id: replacement.id } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    task.update!(assignee: nil)
    delete "#{base}/members/#{membership.id}", headers: headers
    expect(response).to have_http_status(:no_content)
  end

  it 'rejects a foreign account participant and a membership belonging to another project' do
    foreign_user = create(:user, account: create(:account), role: :agent)
    post "#{base}/members", params: { record: { user_id: foreign_user.id, role: 'member', allocation_percent: 100 } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    other = other_project.project_members.create!(account: account, user: member, role: 'member')
    delete "#{base}/members/#{other.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_present
  end

  it 'uploads, lists, opens and removes project files using the real attachment and its audit uploader' do
    upload = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{base}/files", params: { files: [upload] }, headers: headers
    expect(response).to have_http_status(:ok)
    attachment = project.reload.attachments.attachments.first!
    get "#{base}/files", headers: headers
    expect(response).to have_http_status(:ok)
    file = response.parsed_body.fetch('data').find { |row| row['id'] == attachment.id }
    expect(file.fetch('uploaded_by')).to include('id' => admin.id, 'name' => admin.name)
    expect(file.fetch('url')).to be_present
    expect(file.fetch('download_url')).to include('disposition=attachment')
    delete "#{base}/files/#{attachment.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(ActiveStorage::Attachment.exists?(attachment.id)).to be(false)
    events = JrcProjects::AuditEvent.where(account: account, auditable_type: 'JrcProjects::Project', auditable_id: project.id,
                                          action: %w[projects.attachment.added projects.attachment.removed])
    expect(events.pluck(:correlation_id)).to eq(['planning-3c-request', 'planning-3c-request'])
  end

  it 'does not infer an uploader when no matching upload audit exists and rejects an attachment from another project' do
    project.attachments.attach(io: StringIO.new('Legacy evidence'), filename: 'legacy.txt', content_type: 'text/plain')
    get "#{base}/files", headers: headers
    expect(response.parsed_body.dig('data', 0, 'uploaded_by')).to be_nil
    other_project.attachments.attach(io: StringIO.new('Foreign evidence'), filename: 'foreign.txt', content_type: 'text/plain')
    attachment = other_project.attachments.attachments.first!
    delete "#{base}/files/#{attachment.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(ActiveStorage::Attachment.exists?(attachment.id)).to be(true)
  end

  it 'calculates budget from approved time, preserves reported commitment and audits changes' do
    patch "#{base}/budget", params: { budget: { planned_cents: 20_000, committed_cents: 5_000, currency: 'BRL' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post "#{base}/time_entries", params: { time_entry: { task_id: task.id, minutes: 90, worked_on: Date.current } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('data', 'id')
    patch "#{base}/time_entries/#{id}", params: { time_entry: { status: 'approved', hourly_cost_cents: 6_000 } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    project.time_entries.create!(account: account, user: admin, minutes: 60, worked_on: Date.current, status: 'submitted', hourly_cost_cents: 6_000)
    rejected = project.time_entries.create!(account: account, user: admin, minutes: 30, worked_on: Date.current, hourly_cost_cents: 6_000)
    patch "#{base}/time_entries/#{rejected.id}", params: { time_entry: { status: 'rejected' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    project.time_entries.create!(account: account, user: admin, minutes: 60, worked_on: Date.current, status: 'approved')
    get "#{base}/budget", headers: headers
    expect(response.parsed_body.fetch('data')).to include('planned_cents' => 20_000, 'committed_cents' => 5_000,
      'actual_cents' => 9_000, 'remaining_cents' => 11_000, 'basis' => 'approved_time_entries')
    expect(JrcProjects::AuditEvent.where(account: account, auditable_id: project.id, action: 'projects.budget.updated').last!.correlation_id).to eq('planning-3c-request')
  end

  it 'consolidates actual task, team, time and milestone totals without mixing projects' do
    task.update!(due_on: Date.current - 1)
    completed_column = project.board_columns.find_by!(status_key: 'completed')
    project.tasks.create!(account: account, created_by: admin, board_column: completed_column, status: 'completed', title: 'Done', estimated_minutes: 60, due_on: Date.current - 1)
    canceled_column = project.boards.first!.board_columns.create!(account: account, name: 'Canceled', status_key: 'canceled', position: 5)
    project.tasks.create!(account: account, created_by: admin, board_column: canceled_column, status: 'canceled', title: 'Canceled', estimated_minutes: 30, due_on: Date.current - 1)
    project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Subtask', parent: task, estimated_minutes: 45)
    project.time_entries.create!(account: account, user: member, task: task, minutes: 90, worked_on: Date.current)
    project.time_entries.create!(account: account, user: admin, minutes: 60, worked_on: Date.current, status: 'approved')
    project.time_entries.create!(account: account, user: admin, minutes: 30, worked_on: Date.current, status: 'rejected')
    milestone
    project.milestones.create!(account: account, name: 'Complete milestone', status: 'completed', due_on: Date.current + 1)
    project.milestones.create!(account: account, name: 'Undated')
    other_project.milestones.create!(account: account, name: 'Other milestone', due_on: Date.current + 1)
    get base, headers: headers
    data = response.parsed_body.fetch('data')
    expect(data).to include('tasks_total' => 4, 'tasks_completed' => 1, 'progress' => 25, 'contact' => nil)
    expect(data.fetch('overview')).to include('overdue_tasks' => 1, 'team_size' => 2, 'estimated_minutes' => 255, 'worked_minutes' => 150, 'approved_minutes' => 60)
    expect(data.dig('overview', 'upcoming_milestones').map { |row| row['id'] }).to eq([milestone.id])
    expect(data.fetch('recent_activity').none? { |event| event['auditable_type'] == 'JrcProjects::Project' && event['auditable_id'] == other_project.id }).to be(true)
  end

  it 'does not expose financial amounts through project details, time entries or activity to an ordinary member' do
    patch "#{base}/budget", params: { budget: { planned_cents: 999_999, committed_cents: 123_456, currency: 'BRL' } }, headers: headers, as: :json
    post "#{base}/time_entries", params: { time_entry: { minutes: 60, worked_on: Date.current } }, headers: headers, as: :json
    id = response.parsed_body.dig('data', 'id')
    patch "#{base}/time_entries/#{id}", params: { time_entry: { status: 'approved', hourly_cost_cents: 7_654 } }, headers: headers, as: :json
    get base, headers: member_headers
    expect(response).to have_http_status(:ok)
    data = response.parsed_body.fetch('data')
    expect(data).not_to have_key('budget')
    expect(data.fetch('recent_activity').none? { |event| event.key?('before_data') || event.key?('after_data') || event['action'] == 'projects.budget.updated' }).to be(true)
    get "#{base}/time_entries", headers: member_headers
    expect(response.parsed_body.fetch('data').none? { |row| row.key?('hourly_cost_cents') }).to be(true)
    get "#{base}/budget", headers: member_headers
    expect(response).to have_http_status(:forbidden)
    patch "#{base}/budget", params: { budget: { planned_cents: 0 } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    patch "#{base}/time_entries/#{id}", params: { time_entry: { status: 'rejected' } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'enforces viewer permissions for planning, team and file writes while permitting reads' do
    project.project_members.find_by!(user: member).update!(role: 'viewer')
    get "#{base}/milestones", headers: member_headers
    expect(response).to have_http_status(:ok)
    post "#{base}/milestones", params: { record: { name: 'Forbidden' } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    delete "#{base}/milestones/#{milestone.id}", headers: member_headers
    expect(response).to have_http_status(:forbidden)
    post "#{base}/members", params: { record: { user_id: admin.id, role: 'member' } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    project.attachments.attach(io: StringIO.new('Protected evidence'), filename: 'protected.txt', content_type: 'text/plain')
    delete "#{base}/files/#{project.attachments.attachments.first!.id}", headers: member_headers
    expect(response).to have_http_status(:forbidden)
    get "#{base}/files", headers: member_headers
    expect(response).to have_http_status(:ok)
  end

  %w[completed canceled].each do |status|
    it "keeps planning read-only and rejects new time when the project is #{status}" do
      milestone
      task
      successor = project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Successor')
      edge = JrcProjects::Planning::DependencyGraph.add!(predecessor: task, successor: successor)
      project.update!(status: status)
      post "#{base}/milestones", params: { record: { name: 'Forbidden milestone' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      patch "#{base}/milestones/#{milestone.id}", params: { record: { status: 'completed' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      delete "#{base}/milestones/#{milestone.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{base}/dependencies", params: { predecessor_id: task.id, successor_id: successor.id }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      delete "#{base}/dependencies/#{edge.id}", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      patch "#{base}/boards/#{backlog.board_id}/columns/#{backlog.id}", params: { board_column: { name: 'Forbidden rename' } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      post "#{base}/time_entries", params: { time_entry: { minutes: 60, worked_on: Date.current } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      get "#{base}/milestones", headers: headers
      expect(response).to have_http_status(:ok)
      expect(milestone.reload.status).to eq('open')
    end
  end

  it 'rejects access to an account outside the current user membership' do
    foreign_account = create(:account)
    get "/api/v1/accounts/#{foreign_account.id}/projects/projects/#{project.id}/files", headers: headers
    expect(response.status).to be_in([401, 403, 404])
  end
end
