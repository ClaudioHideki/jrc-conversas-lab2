require 'rails_helper'

# Integration coverage groups several adapters under the Migration Center feature.
RSpec.describe JrcMigrations::Adapters::Project do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:dates) { { 'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2024-02-03T12:00:00Z' } }
  let(:project_row) do
    dates.merge('legacy_id' => 'project-1', 'key' => 'HIST-1', 'name' => 'Historical project', 'owner_id' => admin.id,
                'status' => 'completed', 'visibility' => 'members', 'priority' => 'high', 'completed_at' => '2023-04-05T13:00:00Z')
  end

  def preview(domain, row)
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(source: 'fixture', domain: domain, rows: [row], mapping: {})
    JrcMigrations::Preview.new(batch: batch, user: admin).call
    batch
  end

  def execute(batch)
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    batch.reload.items.first
  end

  it 'loads a historical project into the existing module without emitting relationship events' do
    contact = create(:contact, account: account)
    batch = preview('projects', project_row.merge('contact_id' => contact.id))
    expect(batch.items.first.decision).to eq('create')
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch)
    expect { execute(batch) }.not_to change(JrcProjects::OutboxEvent, :count)
    project = JrcProjects::Project.find_by!(account: account, key: 'HIST-1')
    expect(project).to have_attributes(contact_id: contact.id, status: 'completed', priority: 'high', owner_id: admin.id)
    expect(project.completed_at).to eq(Time.iso8601('2023-04-05T13:00:00Z'))
    expect(project.created_at).to eq(Time.iso8601(dates['created_at']))
  end

  it 'resolves project and parent task source keys while retaining status, dates and the same assignee' do
    project = JrcProjects::Project.find(execute(preview('projects', project_row)).target_id)
    JrcProjects::ProjectMember.create!(account: account, project: project, user: admin, role: 'owner')
    task_data = dates.merge('legacy_id' => 'task-1', 'project_legacy_id' => 'project-1', 'title' => 'Historical task',
                            'status' => 'completed', 'priority' => 'high', 'created_by_id' => admin.id, 'assignee_id' => admin.id,
                            'starts_on' => '2022-01-01', 'due_on' => '2022-02-01', 'labels' => [' Imported '])
    task = JrcProjects::Task.find(execute(preview('project_tasks', task_data)).target_id)
    child = JrcProjects::Task.find(execute(preview('project_tasks',
                                                   task_data.merge('legacy_id' => 'task-2', 'parent_legacy_id' => 'task-1'))).target_id)
    expect(child).to have_attributes(project_id: project.id, parent_id: task.id, assignee_id: admin.id, status: 'completed')
    expect(child.due_on).to eq(Date.new(2022, 2, 1))
    expect(child.labels).to eq(['Imported'])
  end

  it 'rejects cross-account owner and project references before creating records' do
    foreign_user = create(:user)
    batch = preview('projects', project_row.merge('owner_id' => foreign_user.id))
    expect(batch.items.first.decision).to eq('reject')
    foreign = create(:account)
    foreign_owner = create(:user, account: foreign)
    project = JrcProjects::Project.create!(account: foreign, owner: foreign_owner, key: 'OTHER', name: 'Other account')
    batch = preview('project_tasks',
                    dates.merge('legacy_id' => 'task-x', 'project_id' => project.id, 'title' => 'Blocked', 'created_by_id' => admin.id))
    expect(batch.items.first.decision).to eq('reject')
  end

  it 'does not merge a native project with a matching key or accept impossible task dates' do
    JrcProjects::Project.create!(account: account, owner: admin, key: 'HIST-1', name: 'Existing')
    expect(preview('projects', project_row).items.first.decision).to eq('review')
    project = JrcProjects::Project.find_by!(account: account, key: 'HIST-1')
    batch = preview('project_tasks', dates.merge('legacy_id' => 'task-x', 'project_id' => project.id, 'title' => 'Bad dates',
                                                 'created_by_id' => admin.id, 'starts_on' => '2023-01-01', 'due_on' => '2022-01-01'))
    expect(batch.items.first.decision).to eq('reject')
  end

  it 'invalidates an editor loaded before a delta through the native optimistic lock' do
    id = execute(preview('projects', project_row)).target_id
    stale_editor = JrcProjects::Project.find(id)
    delta = preview('projects', project_row.merge('name' => 'Imported newer version', 'updated_at' => '2025-01-01T12:00:00Z'))
    execute(delta)
    expect { stale_editor.update!(name: 'Overwrite with old form') }.to raise_error(ActiveRecord::StaleObjectError)
    expect(JrcProjects::Project.find(id).name).to eq('Imported newer version')
  end

  it 'rejects an impossible source project date instead of silently dropping the value' do
    item = preview('projects', project_row.merge('starts_on' => '2021-02-30')).items.first
    expect(item).to have_attributes(decision: 'reject', error_code: 'INVALID_SOURCE_DATES')
  end
end
