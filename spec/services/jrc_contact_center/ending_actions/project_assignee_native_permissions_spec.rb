require 'rails_helper'

# Real native CustomRole/individual/project intersections. All capabilities and
# records below belong only to the explicitly synthetic fixture account.
RSpec.describe 'Native ending task assignee authorization aliases' do
  include_context 'with native ending execution original evidence'

  let(:parameters) do
    version = JrcContactCenter::EndingActionVersion.where(account: account).order(revision: :desc).first!
    version.definition.fetch('entries').first.fetch('actions').first.fetch('parameters').deep_dup
  end
  let(:project) { JrcOperations::Access.projects(member).find(parameters.fetch('project_id')) }
  let(:profile) do
    create(
      :custom_role,
      account: account,
      permissions: %w[jrc_projects_project_view jrc_projects_task_create jrc_projects_task_assign]
    )
  end

  before do
    project
    parameters.fetch('attributes')['assignee_id'] = actor.id.to_s
    member.update!(custom_role: profile)
  end

  it 'does not treat the assign label or administrator role as a substitute for the native update alias' do
    allowed = JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.task.assign', project: project)
    expect(allowed).to be(false)
    expect do
      JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: member).call(parameters)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'assigns the real native task only when the explicit synthetic profile satisfies the existing native alias' do
    profile.update!(permissions: profile.permissions + ['jrc_projects_task_update'])
    allowed = JrcProjects::Authorization.allowed?(account_user: member, capability: 'projects.task.assign', project: project)
    expect(allowed).to be(true)
    task = JrcContactCenter::EndingActions::ProjectTaskDestination.new(account: account, member: member).call(
      parameters: parameters, trigger_at: Time.current, timezone: 'America/Sao_Paulo', correlation_id: SecureRandom.uuid
    )
    expect(task).to have_attributes(account_id: account.id, project_id: project.id, assignee_id: actor.id, created_by_id: actor.id)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').sole.actor_id).to eq(actor.id)
  end
end
