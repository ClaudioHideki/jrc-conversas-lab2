require 'rails_helper'

RSpec.describe JrcProjects::Tasks::Create do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: user, attributes: { name: 'Native task project' },
                                       idempotency_key: SecureRandom.uuid)
  end
  let(:column) { project.board_columns.find_by!(status_key: 'backlog') }
  let(:attributes) { { title: 'Native task', board_column_id: column.id } }

  before do
    account.enable_features!('jrc_projects')
    member.update!(jrc_projects_enabled: true)
  end

  def create_task(values = attributes)
    described_class.call(account_user: member, project: project, attributes: values, correlation_id: 'native-task-spec')
  end

  it 'keeps native column state, position, actor, parent and audit data and accepts zero estimation' do
    parent = create_task
    child = create_task(attributes.merge(title: 'Native child', parent_id: parent.id, estimated_minutes: 0, assignee_id: user.id))
    expect(child).to have_attributes(account_id: account.id, project_id: project.id, parent_id: parent.id, created_by_id: user.id,
                                     assignee_id: user.id, board_column_id: column.id, status: 'backlog', position: 2048, estimated_minutes: 0)
    audit = JrcProjects::AuditEvent.find_by!(action: 'projects.task.created', auditable_type: child.class.name, auditable_id: child.id)
    expect(audit).to have_attributes(actor_id: user.id, correlation_id: 'native-task-spec')
    expect(audit.after_data).to include('id' => child.id, 'parent_id' => parent.id)
  end

  it 'preserves the HTTP first-column default but rejects a completed column and a full WIP column' do
    task = create_task(title: 'HTTP default column')
    expect(task.board_column_id).to eq(column.id)
    complete = project.board_columns.find_by!(status_key: 'completed')
    expect { create_task(attributes.merge(board_column_id: complete.id)) }.to raise_error(ArgumentError, /coluna de trabalho/)
    column.update!(wip_limit: 1)
    expect { create_task }.to raise_error(JrcProjects::Errors::WipLimit)
    expect(project.tasks.count).to eq(1)
  end

  it 'rejects a foreign project column and a parent from another project without task or audit writes' do
    other = JrcProjects::Projects::Create.call(account: account, actor: user, attributes: { name: 'Different project' },
                                               idempotency_key: SecureRandom.uuid)
    other_task = described_class.call(account_user: member, project: other, attributes: { title: 'Other parent' })
    project # Materialize the native project and its creation audit before the no-write baseline.
    count = JrcProjects::AuditEvent.count
    expect { create_task(attributes.merge(board_column_id: other.board_columns.first!.id)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { create_task(attributes.merge(parent_id: other_task.id)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(project.tasks).to be_empty
    expect(JrcProjects::AuditEvent.count).to eq(count)
  end

  it 'rejects an assignee with no native project membership and a completed project' do
    colleague = create(:user, account: account)
    expect { create_task(attributes.merge(assignee_id: colleague.id)) }.to raise_error(ActiveRecord::RecordNotFound)
    project.update!(status: 'completed')
    expect { create_task }.to raise_error(ArgumentError, /Reabra o projeto/)
    expect(project.tasks).to be_empty
  end

  it 'refreshes the original AccountUser grant and denies creation after revocation' do
    project
    member.update!(jrc_projects_enabled: false)
    expect { create_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(project.tasks).to be_empty
    expect(JrcProjects::AuditEvent.where(action: 'projects.task.created')).to be_empty
  end
end
