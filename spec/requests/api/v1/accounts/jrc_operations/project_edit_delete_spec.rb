require 'rails_helper'

RSpec.describe 'JRC Projects editing and deletion', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { admin.create_new_auth_token }
  let(:agent_headers) { agent.create_new_auth_token }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: admin, attributes: { name: 'Projeto para revisão' }, idempotency_key: SecureRandom.uuid)
  end
  let(:task) do
    project.tasks.create!(account: account, created_by: admin, board_column: project.board_columns.find_by!(status_key: 'backlog'),
                          status: 'backlog', title: 'Tarefa principal')
  end
  let(:base) { "/api/v1/accounts/#{account.id}/projects/projects/#{project.id}" }

  before do
    account.enable_features!('jrc_projects')
    account.account_users.find_by!(user: agent).update!(jrc_projects_enabled: true)
    project.project_members.create!(account: account, user: agent, role: 'member')
  end

  it 'deletes the entire internal tree in one transaction and retains the deletion audit' do
    parent = task
    child = project.tasks.create!(account: account, created_by: admin, parent: parent, title: 'Subtarefa',
                                  board_column: parent.board_column, status: 'backlog')
    child.checklist_items.create!(account: account, text: 'Validar')
    child.task_comments.create!(account: account, user: admin, body: 'Nota interna')
    project.milestones.create!(account: account, name: 'Entrega')
    project.sprints.create!(account: account, name: 'Primeiro ciclo', status: 'planned')
    project.risks.create!(account: account, title: 'Risco', status: 'open')
    project.issues.create!(account: account, title: 'Impedimento', status: 'open')
    project.decisions.create!(account: account, title: 'Decisão', status: 'open')
    project_id = project.id

    delete base, params: { lock_version: project.lock_version }, headers: headers, as: :json

    expect(response).to have_http_status(:no_content)
    expect(JrcProjects::Project.exists?(project_id)).to be(false)
    expect(JrcProjects::Task.where(project_id: project_id)).to be_empty
    expect(JrcProjects::Board.where(project_id: project_id)).to be_empty
    expect(JrcProjects::Milestone.where(project_id: project_id)).to be_empty
    expect(JrcProjects::AuditEvent.find_by!(auditable_id: project_id, action: 'projects.project.deleted').before_data).to include('name' => 'Projeto para revisão')
  end

  it 'requires the current project version and keeps data after a stale deletion' do
    task
    delete base, params: { lock_version: project.lock_version - 1 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(project.reload.tasks.count).to eq(1)
    expect(JrcProjects::AuditEvent.where(auditable_id: project.id, action: 'projects.project.deleted')).to be_empty
  end

  it 'denies project deletion to a member even with access to the project' do
    delete base, params: { lock_version: project.lock_version }, headers: agent_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcProjects::Project.exists?(project.id)).to be(true)
  end

  it 'preserves a project containing logged work' do
    entry = project.time_entries.create!(account: account, user: admin, task: task, minutes: 45, worked_on: Date.current)
    delete base, params: { lock_version: project.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(project.reload.tasks.exists?(task.id)).to be(true)
    expect(JrcProjects::TimeEntry.exists?(entry.id)).to be(true)
  end

  it 'exposes task deletion capability and rejects a stale task deletion' do
    get "#{base}/tasks/#{task.id}", headers: headers
    expect(response.parsed_body.dig('data', 'can_delete')).to be(true)
    get "#{base}/tasks/#{task.id}", headers: agent_headers
    expect(response.parsed_body.dig('data', 'can_delete')).to be(false)
    delete "#{base}/tasks/#{task.id}", params: { lock_version: -1 }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcProjects::Task.exists?(task.id)).to be(true)
  end

  it 'lets authors edit and delete their own task comments and audits both actions' do
    comment = task.task_comments.create!(account: account, user: agent, body: 'Antes')
    path = "#{base}/tasks/#{task.id}/comments/#{comment.id}"
    patch path, params: { comment: { body: 'Depois' } }, headers: agent_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(comment.reload.body).to eq('Depois')
    delete path, headers: agent_headers
    expect(response).to have_http_status(:no_content)
    expect(JrcProjects::TaskComment.exists?(comment.id)).to be(false)
    expect(JrcProjects::AuditEvent.where(auditable_id: task.id, action: %w[projects.task.comment_updated projects.task.comment_deleted]).count).to eq(2)
  end

  it 'does not let a member overwrite another author comment' do
    comment = task.task_comments.create!(account: account, user: admin, body: 'Nota do gestor')
    path = "#{base}/tasks/#{task.id}/comments/#{comment.id}"
    patch path, params: { comment: { body: 'Tentativa' } }, headers: agent_headers, as: :json
    expect(response).to have_http_status(:forbidden)
    delete path, headers: agent_headers
    expect(response).to have_http_status(:forbidden)
    expect(comment.reload.body).to eq('Nota do gestor')
  end

  it 'scopes comments to their task and does not allow cross-task edits' do
    other = project.tasks.create!(account: account, created_by: admin, title: 'Outra tarefa',
                                  board_column: task.board_column, status: 'backlog')
    comment = other.task_comments.create!(account: account, user: admin, body: 'Outro contexto')
    patch "#{base}/tasks/#{task.id}/comments/#{comment.id}", params: { comment: { body: 'Tentativa' } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(comment.reload.body).to eq('Outro contexto')
  end

  it 'allows an agent to edit and remove their submitted time entry without touching another user work' do
    own = project.time_entries.create!(account: account, user: agent, minutes: 30, worked_on: Date.current)
    another = project.time_entries.create!(account: account, user: admin, minutes: 40, worked_on: Date.current)
    patch "#{base}/time_entries/#{own.id}", params: { time_entry: { task_id: task.id, minutes: 90, notes: 'Revisado' } }, headers: agent_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(own.reload).to have_attributes(task_id: task.id, minutes: 90, notes: 'Revisado')
    delete "#{base}/time_entries/#{another.id}", headers: agent_headers
    expect(response).to have_http_status(:forbidden)
    delete "#{base}/time_entries/#{own.id}", headers: agent_headers
    expect(response).to have_http_status(:no_content)
    expect(JrcProjects::TimeEntry.exists?(another.id)).to be(true)
    expect(JrcProjects::AuditEvent.where(auditable_id: own.id, action: 'projects.time_entry.deleted')).to exist
  end

  it 'protects approved hours and closed projects from time deletion' do
    entry = project.time_entries.create!(account: account, user: admin, minutes: 60, worked_on: Date.current, status: 'approved')
    delete "#{base}/time_entries/#{entry.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    entry.update!(status: 'submitted')
    project.update!(status: 'canceled')
    delete "#{base}/time_entries/#{entry.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcProjects::TimeEntry.exists?(entry.id)).to be(true)
  end

  it 'creates and edits phases while preventing deletion of a phase used by a milestone' do
    post "#{base}/phases", params: { record: { name: 'Implantação', position: 1, starts_on: '2026-10-23', ends_on: '2026-10-30' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    phase = project.phases.find(response.parsed_body.dig('data', 'id'))
    patch "#{base}/phases/#{phase.id}", params: { record: { name: 'Validação' } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    milestone = project.milestones.create!(account: account, name: 'Aceite', phase: phase)
    delete "#{base}/phases/#{phase.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    milestone.update!(phase: nil)
    delete "#{base}/phases/#{phase.id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(JrcProjects::AuditEvent.where(auditable_id: phase.id, action: 'projects.phase.deleted')).to exist
  end
end
