require 'rails_helper'

RSpec.describe JrcContactCenter::EndingActions::ProjectTaskDestination do
  subject(:destination) { described_class.new(account: account, member: member) }

  include_context 'with native ending execution original evidence'

  let(:parameters) do
    version = JrcContactCenter::EndingActionVersion.where(account: account).order(revision: :desc).first!
    version.definition.fetch('entries').first.fetch('actions').first.fetch('parameters').deep_dup
  end
  let(:project) { JrcOperations::Access.projects(member).find(parameters.fetch('project_id')) }
  let(:trigger_at) { Time.iso8601('2026-11-23T01:30:00Z') }
  let(:request_key) { SecureRandom.uuid }

  def create_destination_task(adapter = destination)
    adapter.call(parameters: parameters, trigger_at: trigger_at, timezone: 'America/Sao_Paulo', correlation_id: request_key)
  end

  it 'creates the real native task and native project audit with the supplied technical correlation' do
    task = create_destination_task
    expect(task).to be_persisted
    expect(task.attributes.slice('account_id', 'project_id', 'created_by_id', 'title', 'status')).to eq(
      'account_id' => account.id, 'project_id' => project.id, 'created_by_id' => actor.id,
      'title' => parameters.fetch('attributes').fetch('title'), 'status' => 'backlog'
    )
    audit = JrcProjects::AuditEvent.find_by!(account: account, auditable_type: task.class.name, auditable_id: task.id)
    expect(audit).to have_attributes(actor_id: actor.id, action: 'projects.task.created', correlation_id: request_key)
    expect(task.due_on).to be_nil
  end

  it 'anchors zero-day deadlines to the immutable trigger date in the reviewed source timezone' do
    parameters['due_after_days'] = 0
    travel_to(Time.iso8601('2026-12-15T12:00:00Z')) do
      expect(create_destination_task.due_on).to eq(Date.iso8601('2026-11-22'))
    end
    expect(parameters['due_after_days']).to eq(0)
    expect(parameters.fetch('attributes')).not_to have_key('due_on')
  end

  it 'preserves explicit absolute dates and optional native labels and description without copying call content' do
    parameters.fetch('attributes').merge!('starts_on' => '2026-11-22', 'due_on' => '2026-11-24',
                                        'description' => 'SYNTHETIC configured description', 'labels' => ['SYNTHETIC'])
    task = create_destination_task
    expect(task).to have_attributes(starts_on: Date.iso8601('2026-11-22'), due_on: Date.iso8601('2026-11-24'),
                                   description: 'SYNTHETIC configured description', labels: ['SYNTHETIC'])
  end

  it 'does not invent a timezone when a relative deadline lacks its reviewed source timezone' do
    parameters['due_after_days'] = 1
    expect do
      destination.call(parameters: parameters, trigger_at: trigger_at, timezone: nil, correlation_id: request_key)
    end.to raise_error(JrcContactCenter::OperationError, 'ending_action_timezone_unavailable')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects a derived deadline before an explicit start instead of silently moving the start date' do
    parameters['due_after_days'] = 0
    parameters.fetch('attributes')['starts_on'] = '2026-11-23'
    expect { create_destination_task }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'revalidates the destination feature on a later attempt' do
    first = create_destination_task
    account.disable_features!('jrc_projects')
    expect { create_destination_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account).pluck(:id)).to eq([first.id])
  end

  it 'does not use a source administrator as a grant to a now private project' do
    project.update!(visibility: 'private', owner_id: create(:user, account: account).id)
    project.project_members.where(account: account, user: actor).find_each(&:destroy!)
    member.update!(role: :agent, jrc_projects_permissions: {})
    expect { create_destination_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rechecks current destination permissions after a custom role becomes restrictive' do
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    member.update!(custom_role: role)
    expect { create_destination_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rejects an account mismatch without treating a valid project reference as authority' do
    other = create(:account)
    adapter = described_class.new(account: other, member: member)
    expect { create_destination_task(adapter) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'retains the native WIP limit and creates neither a task nor a success audit on failure' do
    column = project.board_columns.find(parameters.fetch('attributes').fetch('board_column_id'))
    column.update!(wip_limit: 1)
    first = create_destination_task
    expect { create_destination_task }.to raise_error(JrcProjects::Errors::WipLimit)
    expect(JrcProjects::Task.where(account: account).pluck(:id)).to eq([first.id])
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count).to eq(1)
  end

  it 'retains native project and column state restrictions' do
    project.update!(status: 'completed')
    expect { create_destination_task }.to raise_error(JrcContactCenter::OperationError, 'invalid_ending_task_parameters')
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'uses the explicitly configured native project member instead of assigning the executor implicitly' do
    assignee = create(:user, account: account)
    JrcProjects::ProjectMember.create!(account: account, project: project, user: assignee, role: 'member')
    parameters.fetch('attributes')['assignee_id'] = assignee.id.to_s
    expect(create_destination_task).to have_attributes(assignee_id: assignee.id, created_by_id: actor.id)
  end

  it 'refuses an assignee removed from the native project before an attempt' do
    assignee = create(:user, account: account)
    assignment = JrcProjects::ProjectMember.create!(account: account, project: project, user: assignee, role: 'member')
    parameters.fetch('attributes')['assignee_id'] = assignee.id.to_s
    assignment.destroy!
    expect { create_destination_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'rolls the actual native task and its native audit back when the enclosing receipt savepoint fails' do
    expect do
      ApplicationRecord.transaction(requires_new: true) do
        create_destination_task
        raise JrcContactCenter::OperationError, 'SYNTHETIC_receipt_write_failure'
      end
    end.to raise_error(JrcContactCenter::OperationError, 'SYNTHETIC_receipt_write_failure')
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created')).to be_empty
  end
end
