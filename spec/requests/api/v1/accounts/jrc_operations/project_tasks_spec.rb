require 'rails_helper'

# Real requests against Rails, PostgreSQL and ActiveStorage. Run only against a
# dedicated test database with the existing migrations. Not executed by Node.
RSpec.describe 'JRC Projects tasks and Kanban checkpoint 3B', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token.merge('X-Request-Id' => 'tasks-3b-request') }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Task delivery' }, idempotency_key: SecureRandom.uuid)
  end
  let(:other_project) do
    JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Other delivery' }, idempotency_key: SecureRandom.uuid)
  end
  let(:backlog) { project.board_columns.find_by!(status_key: 'backlog') }
  let(:in_progress) { project.board_columns.find_by!(status_key: 'in_progress') }
  let(:completed) { project.board_columns.find_by!(status_key: 'completed') }
  let(:task) do
    project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'First task', position: 1024)
  end
  let(:other_task) do
    column = other_project.board_columns.find_by!(status_key: 'backlog')
    other_project.tasks.create!(account: account, created_by: admin, board_column: column, status: 'backlog', title: 'Other project task')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}" }
  let(:tasks_url) { "#{base}/tasks" }
  let(:task_url) { "#{tasks_url}/#{task.id}" }
  let(:fixture_path) { Rails.root.join('spec/fixtures/files/jrc_projects_task.txt') }

  before do
    account.account_users.find_by!(user: member).update!(jrc_projects_enabled: true)
    account.enable_features!('jrc_projects')
    project.project_members.create!(account: account, user: member, role: 'member')
  end

  it 'creates, reads, edits and assigns a task with labels, parent and estimates' do
    parent = task
    post tasks_url, params: { task: { title: 'Child task', description: 'Internal scope', priority: 'high', assignee_id: member.id,
                                    parent_id: parent.id, labels: [' Infra ', 'Infra', 'PABX'], estimated_minutes: 120,
                                    starts_on: '2026-10-01', due_on: '2026-10-10', board_column_id: backlog.id } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    data = response.parsed_body.fetch('data')
    child = JrcProjects::Task.find(data.fetch('id'))
    expect(child).to have_attributes(parent_id: parent.id, assignee_id: member.id, priority: 'high', estimated_minutes: 120)
    expect(child.custom_fields).to include('labels' => %w[Infra PABX])
    expect(data).to include('labels' => %w[Infra PABX], 'worked_minutes' => 0, 'can_update' => true, 'can_move' => true)
    patch "#{tasks_url}/#{child.id}", params: { task: { title: 'Edited child', description: 'Updated scope', assignee_id: nil,
                                                      labels: ['Delivery'], lock_version: child.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(child.reload).to have_attributes(title: 'Edited child', assignee_id: nil, parent_id: parent.id, labels: ['Delivery'])
    get task_url, headers: headers
    expect(response.parsed_body.dig('data', 'subtasks').pluck('id')).to include(child.id)
    events = JrcProjects::AuditEvent.where(account: account, auditable_id: child.id, action: %w[projects.task.created projects.task.updated])
    expect(events.pluck(:action)).to contain_exactly('projects.task.created', 'projects.task.updated')
    expect(events.pluck(:correlation_id).uniq).to eq(['tasks-3b-request'])
  end

  it 'preserves unrelated custom_fields while editing labels and rejects parent cycles' do
    task.update!(custom_fields: { 'integration_reference' => 'preserve', 'labels' => ['Old'] })
    patch task_url, params: { task: { labels: ['New'], lock_version: task.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(task.reload.custom_fields).to include('integration_reference' => 'preserve', 'labels' => ['New'])
    child = project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Child', parent: task)
    [task.id, child.id].each do |parent_id|
      patch task_url, params: { task: { parent_id: parent_id, lock_version: task.reload.lock_version } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.parent_id).to be_nil
    end
  end

  it 'rejects a nonmember assignee, foreign account user, foreign column and foreign parent' do
    nonmember = create(:user, account: account, role: :agent)
    foreign_account = create(:account)
    foreign_user = create(:user, account: foreign_account, role: :agent)
    [nonmember, foreign_user].each do |user|
      post tasks_url, params: { task: { title: 'Invalid assignment', assignee_id: user.id } }, headers: headers, as: :json
      expect(response).to have_http_status(:not_found)
    end
    post tasks_url, params: { task: { title: 'Invalid column', board_column_id: other_task.board_column_id } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    patch task_url, params: { task: { parent_id: other_task.id, lock_version: task.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(task.reload.parent_id).to be_nil
  end

  it 'scopes task reads, edits, comments and files by project even for admins' do
    foreign_path = "#{tasks_url}/#{other_task.id}"
    [foreign_path, "#{foreign_path}/comments", "#{foreign_path}/files"].each do |path|
      get path, headers: headers
      expect(response).to have_http_status(:not_found)
    end
    patch foreign_path, params: { task: { title: 'Forbidden edit', lock_version: other_task.lock_version } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(other_task.reload.title).to eq('Other project task')
  end

  it 'rejects a project and task owned by another account' do
    foreign_account = create(:account)
    foreign_account.enable_features!('jrc_projects')
    foreign_user = create(:user, account: foreign_account, role: :administrator)
    foreign_project = JrcProjects::Projects::Create.call(account: foreign_account, actor: foreign_user,
      attributes: { name: 'Foreign delivery' }, idempotency_key: SecureRandom.uuid)
    column = foreign_project.board_columns.first!
    foreign_task = foreign_project.tasks.create!(account: foreign_account, created_by: foreign_user, title: 'Foreign task',
                                                board_column: column, status: column.status_key)
    get "/api/v1/accounts/#{account.id}/projects/projects/#{foreign_project.id}/tasks", headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{base}/dependencies", params: { predecessor_id: foreign_task.id, successor_id: task.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'respects viewer and contributor task permissions' do
    membership = project.project_members.find_by!(user: member)
    membership.update!(role: 'viewer')
    member_headers = member.create_new_auth_token
    get task_url, headers: member_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('data', 'can_update')).to be(false)
    patch task_url, params: { task: { title: 'Forbidden', lock_version: task.lock_version } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    membership.update!(role: 'contributor')
    patch task_url, params: { task: { title: 'Still forbidden', lock_version: task.lock_version } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    task.update!(assignee: member)
    patch task_url, params: { task: { title: 'Assigned contributor edit', lock_version: task.lock_version } }, headers: member_headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'enforces stale lock_version on edit and movement without adding success audit' do
    task
    expect do
      patch task_url, params: { task: { title: 'Stale', lock_version: -1 } }, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
      post "#{task_url}/move", params: { column_id: in_progress.id, lock_version: -1 }, headers: headers, as: :json
      expect(response).to have_http_status(:conflict)
    end.not_to change(JrcProjects::AuditEvent, :count)
    expect(task.reload).to have_attributes(title: 'First task', board_column_id: backlog.id)
  end

  it 'moves through real column ids and updates the existing project progress calculation' do
    task
    project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Pending', position: 2048)
    [in_progress, project.board_columns.find_by!(status_key: 'review'), completed].each do |column|
      post "#{task_url}/move", params: { column_id: column.id, lock_version: task.reload.lock_version }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(task.reload).to have_attributes(board_column_id: column.id, status: column.status_key)
    end
    get base, headers: headers
    expect(response.parsed_body.fetch('data')).to include('tasks_total' => 2, 'tasks_completed' => 1, 'progress' => 50)
    expect(JrcProjects::AuditEvent.where(auditable_id: task.id, action: 'projects.task.moved').pluck(:correlation_id)).to eq(['tasks-3b-request'] * 3)
  end

  it 'does not change position, version or audit for a same-column no-op move' do
    task
    project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Second', position: 2048)
    old_version = task.lock_version
    expect do
      post "#{task_url}/move", params: { column_id: backlog.id, lock_version: old_version }, headers: headers, as: :json
    end.not_to change(JrcProjects::AuditEvent, :count)
    expect(response).to have_http_status(:ok)
    expect(task.reload).to have_attributes(position: 1024, lock_version: old_version)
  end

  it 'preserves WIP and rejects before_task_id or columns from another project' do
    task
    in_progress.update!(wip_limit: 1)
    occupant = project.tasks.create!(account: account, created_by: admin, board_column: in_progress, status: 'in_progress', title: 'WIP occupant')
    post "#{task_url}/move", params: { column_id: in_progress.id, lock_version: task.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(task.reload.board_column_id).to eq(backlog.id)
    post "#{task_url}/move", params: { column_id: other_task.board_column_id, lock_version: task.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{task_url}/move", params: { column_id: in_progress.id, before_task_id: other_task.id, lock_version: task.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(occupant.reload.board_column_id).to eq(in_progress.id)
  end

  it 'blocks completion for pending predecessors but allows a canceled predecessor' do
    predecessor = task
    successor = project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Successor', position: 2048)
    post "#{base}/dependencies", params: { predecessor_id: predecessor.id, successor_id: successor.id, kind: 'finish_to_start' }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    post "#{tasks_url}/#{successor.id}/move", params: { column_id: completed.id, lock_version: successor.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    canceled = project.boards.first!.board_columns.create!(account: account, name: 'Canceled', status_key: 'canceled', position: 5)
    post "#{task_url}/move", params: { column_id: canceled.id, lock_version: predecessor.reload.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post "#{tasks_url}/#{successor.id}/move", params: { column_id: completed.id, lock_version: successor.reload.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(successor.reload.status).to eq('completed')
  end

  it 'adds an edge from a canceled predecessor to an already completed successor' do
    canceled = project.boards.first!.board_columns.create!(account: account, name: 'Canceled', status_key: 'canceled', position: 5)
    task.update!(board_column: canceled, status: 'canceled')
    successor = project.tasks.create!(account: account, created_by: admin, board_column: completed, status: 'completed', title: 'Done')
    post "#{base}/dependencies", params: { predecessor_id: task.id, successor_id: successor.id }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end

  it 'adds only one dependency and one dependency_added event for repeated requests' do
    successor = project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Successor')
    2.times do
      post "#{base}/dependencies", params: { predecessor_id: task.id, successor_id: successor.id }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
    end
    expect(JrcProjects::TaskDependency.where(predecessor: task, successor: successor).count).to eq(1)
    expect(JrcProjects::AuditEvent.where(auditable_id: successor.id, action: 'projects.task.dependency_added').count).to eq(1)
  end

  it 'rejects cross-project dependencies, cycles and unsupported dependency kinds' do
    post "#{base}/dependencies", params: { predecessor_id: other_task.id, successor_id: task.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    successor = project.tasks.create!(account: account, created_by: admin, board_column: backlog, status: 'backlog', title: 'Successor')
    post "#{base}/dependencies", params: { predecessor_id: task.id, successor_id: successor.id }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    post "#{base}/dependencies", params: { predecessor_id: successor.id, successor_id: task.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/dependencies", params: { predecessor_id: task.id, successor_id: successor.id, kind: 'start_to_start' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps checklist changes scoped to the task and does not repeat no-op audit' do
    post "#{task_url}/checklist_items", params: { item: { text: 'Validate delivery', completed: false } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('data', 'id')
    2.times do
      patch "#{task_url}/checklist_items/#{id}", params: { item: { completed: true } }, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
    end
    expect(JrcProjects::AuditEvent.where(auditable_id: task.id, action: 'projects.task.checklist_updated').count).to eq(1)
    alien = other_task.checklist_items.create!(account: account, text: 'Other checklist')
    patch "#{task_url}/checklist_items/#{alien.id}", params: { item: { completed: true } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    delete "#{task_url}/checklist_items/#{id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(JrcProjects::ChecklistItem.exists?(id)).to be(false)
  end

  it 'stores comments only on their task without sending messages' do
    task
    expect do
      post "#{task_url}/comments", params: { comment: { body: 'Internal technical note', task_id: other_task.id } }, headers: headers, as: :json
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:created)
    expect(task.task_comments.pluck(:body)).to eq(['Internal technical note'])
    expect(other_task.task_comments).to be_empty
    get "#{task_url}/comments", headers: headers
    expect(response.parsed_body.fetch('data').pluck('task_id')).to eq([task.id])
    expect(JrcProjects::AuditEvent.where(auditable_id: task.id, action: 'projects.task.comment_added').last!.correlation_id).to eq('tasks-3b-request')
  end

  it 'records task hours and reports valid logged totals without leaking hourly cost to members' do
    post "#{base}/time_entries", params: { time_entry: { task_id: task.id, minutes: 90, worked_on: '2026-09-24', notes: 'Internal work' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    entry = JrcProjects::TimeEntry.find(response.parsed_body.dig('data', 'id'))
    entry.update!(hourly_cost_cents: 5000)
    project.time_entries.create!(account: account, user: admin, task: task, minutes: 30, worked_on: '2026-09-24', status: 'rejected')
    get task_url, headers: headers
    expect(response.parsed_body.dig('data', 'worked_minutes')).to eq(90)
    get "#{base}/time_entries", headers: member.create_new_auth_token
    expect(response.parsed_body.fetch('data').all? { |row| !row.key?('hourly_cost_cents') }).to be(true)
  end

  it 'rejects time entries and updates crossing project boundaries' do
    post "#{base}/time_entries", params: { time_entry: { task_id: other_task.id, minutes: 30, worked_on: '2026-09-24' } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    entry = other_project.time_entries.create!(account: account, user: admin, task: other_task, minutes: 30, worked_on: '2026-09-24')
    patch "#{base}/time_entries/#{entry.id}", params: { time_entry: { minutes: 99 } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(entry.reload.minutes).to eq(30)
  end

  %w[completed canceled].each do |status|
    it "blocks new time on a #{status} project in both controller and model" do
      task
      project.update!(status: status)
      expect do
        post "#{base}/time_entries", params: { time_entry: { task_id: task.id, minutes: 60, worked_on: '2026-09-24' } }, headers: headers, as: :json
      end.not_to change(JrcProjects::TimeEntry, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      direct = project.time_entries.new(account: account, user: admin, task: task, minutes: 60, worked_on: '2026-09-24')
      expect(direct).not_to be_valid
    end
  end

  it 'uploads, serializes and removes through the real ActiveStorage attachment collection' do
    upload = fixture_file_upload(fixture_path, 'text/plain')
    post "#{task_url}/files", params: { files: [upload] }, headers: headers
    expect(response).to have_http_status(:ok)
    attachment = task.reload.attachments.attachments.first!
    expect(response.parsed_body.fetch('data')).to include(hash_including('id' => attachment.id, 'name' => 'jrc_projects_task.txt'))
    get "#{task_url}/files", headers: headers
    expect(response.parsed_body.dig('data', 0, 'url')).to be_present
    delete "#{task_url}/files/#{attachment.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(ActiveStorage::Attachment.exists?(attachment.id)).to be(false)
    expect(JrcProjects::AuditEvent.where(auditable_id: task.id, action: 'projects.attachment.removed').last!.correlation_id).to eq('tasks-3b-request')
  end

  it 'cannot remove another task attachment even when its id is known' do
    other_task.attachments.attach(io: StringIO.new('Other task evidence'), filename: 'foreign.txt', content_type: 'text/plain')
    attachment = other_task.attachments.attachments.first!
    delete "#{task_url}/files/#{attachment.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(ActiveStorage::Attachment.exists?(attachment.id)).to be(true)
  end
end
