# frozen_string_literal: true

RSpec.shared_context 'with native manual recording task destination' do
  include_context 'with native authorized quality review source'

  let(:project_owner) { create(:user, account: account, role: :administrator) }
  let(:project) do
    owner = account.account_users.find_by!(user: project_owner)
    JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: owner, user: project_owner) do
      JrcProjects::Projects::Create.call(account: account, actor: project_owner,
                                         attributes: { name: 'SYNTHETIC manual call task project', visibility: 'private' },
                                         idempotency_key: SecureRandom.uuid)
    end
  end
  let(:project_rights) { %w[projects.project.view projects.task.view projects.task.create projects.task.assign projects.member.view] }
  let(:request_id) { SecureRandom.uuid }
  let(:input) do
    { 'project_id' => project.id.to_s, 'request_id' => request_id, 'task' => {
      'title' => 'SYNTHETIC manual call task', 'priority' => 'medium', 'estimated_minutes' => 0,
      'assignee_id' => actor.id.to_s, 'due_on' => '2026-12-02',
      'board_column_id' => project.board_columns.find_by!(status_key: 'backlog').id.to_s
    } }
  end

  before do
    account.enable_features!('jrc_projects')
    role.update!(permissions: recording_rights + project_rights.map { |right| JrcProjects::Authorization.permission(right) })
    member.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.task.create' => true, 'projects.task.assign' => true })
    JrcProjects::ProjectMember.create!(account: account, project: project, user: actor, role: 'member')
  end

end
