# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcContactCenter::RecordingTaskWrite, :pabx do
  include_context 'with native manual recording task destination'

  def create_call_task(values = input)
    described_class.new(account: account, member: member).call(record.id, values)
  end

  def native_effect_counts
    [JrcProjects::Task.where(account: account).count, JrcContactCenter::RecordingTaskLink.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count]
  end

  it 'creates one real native task and immutable call link with current actor and native audit correlation' do
    row = create_call_task
    task = JrcProjects::Task.where(account: account).sole
    expect(native_effect_counts).to eq([1, 1, 1])
    expect(row).to have_attributes(recording_id: record.id, call_session_id: source_call.id, task_id: task.id, project_id: project.id,
                                   created_by_id: actor.id, actor_account_user_id: member.id, idempotency_key: request_id)
    expect(task).to have_attributes(title: input.fetch('task').fetch('title'), assignee_id: actor.id,
                                    due_on: Date.new(2026, 12, 2), status: 'backlog')
    expect(row.scope_snapshot).to include('account_id' => account.id.to_s, 'unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').sole.correlation_id).to eq(request_id)
  end

  it 'does not fetch an AI source, start or complete ACW, confirm a reason or dispatch an automation' do
    counts = [JrcContactCenter::Qualification.count, JrcContactCenter::EndingActionOrigin.count, JrcContactCenter::Command.count]
    expect(provider).not_to receive(:find_analysis)
    create_call_task
    expect([JrcContactCenter::Qualification.count, JrcContactCenter::EndingActionOrigin.count, JrcContactCenter::Command.count]).to eq(counts)
    expect(native_effect_counts).to eq([1, 1, 1])
  end

  it 'returns the same real receipt for an identical repeated request without creating another task or audit' do
    first = create_call_task
    original = first.attributes
    second = create_call_task(input.deep_dup)
    expect(second.id).to eq(first.id)
    expect(second.attributes).to eq(original)
    expect(native_effect_counts).to eq([1, 1, 1])
  end

  it 'rejects a changed task body with an existing request key and preserves the original native effect' do
    first = create_call_task
    changed = input.deep_dup
    changed.fetch('task')['title'] = 'SYNTHETIC conflicting second title'
    expect { create_call_task(changed) }.to raise_error(JrcContactCenter::OperationError, 'recording_task_request_conflict')
    expect(native_effect_counts).to eq([1, 1, 1])
    expect(JrcProjects::Task.find(first.task_id).title).to eq(input.fetch('task').fetch('title'))
  end

  it 'requires current native create authority again even when the same request already succeeded' do
    create_call_task
    member.update!(jrc_projects_permissions: { 'projects.task.create' => false, 'projects.task.assign' => true })
    expect { create_call_task }.to raise_error(Pundit::NotAuthorizedError)
    expect(native_effect_counts).to eq([1, 1, 1])
  end

  it 'requires current recording listening authority independently of Project and human-review permissions' do
    role.update!(permissions: role.permissions - ['jrc_contact_center_recordings_listen'])
    expect { create_call_task }.to raise_error(Pundit::NotAuthorizedError)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'does not grant native assignment permission through a selected assignee or source recording' do
    member.update!(jrc_projects_permissions: { 'projects.task.create' => true, 'projects.task.assign' => false })
    expect { create_call_task }.to raise_error(Pundit::NotAuthorizedError)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'immediately rejects the source after its current corporate coverage is withdrawn' do
    account.jrc_crm_user_business_units.where(user: actor).find_each { |coverage| coverage.update!(active: false) }
    expect { create_call_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'does not expose a private Project or create a task after native membership is withdrawn' do
    project.project_members.where(account: account, user: actor).sole.destroy!
    expect { create_call_task }.to raise_error(ActiveRecord::RecordNotFound)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'rejects a mismatched account/member at the service boundary without touching another account' do
    foreign = create(:account)
    expect { described_class.new(account: foreign, member: member).call(record.id, input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(native_effect_counts).to eq([0, 0, 0])
    expect(JrcContactCenter::RecordingTaskLink.where(account: foreign)).to be_empty
  end

  it 'preserves native WIP refusal without creating a receipt or a fabricated task number' do
    create_call_task
    project.board_columns.find_by!(status_key: 'backlog').update!(wip_limit: 1)
    changed = input.merge('request_id' => SecureRandom.uuid)
    expect { create_call_task(changed) }.to raise_error(JrcProjects::Errors::WipLimit)
    expect(native_effect_counts).to eq([1, 1, 1])
  end

  it 'rolls back the real native task and native audit when PostgreSQL rejects a malformed source-link snapshot' do
    writer = described_class.new(account: account, member: member)
    scope = JrcContactCenter::ConfigurationAuditSnapshot.capture(queue).fetch('scope').merge('unit_id' => '999999999')
    # Internal fault injection only: the real native Task write and the actual SQL trigger remain active.
    allow(writer).to receive(:scope_for).and_return(scope)
    expect do
      ApplicationRecord.transaction(requires_new: true) { writer.call(record.id, input) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(native_effect_counts).to eq([0, 0, 0])
  end

  it 'keeps the receipt immutable under direct SQL and preserves the native task unchanged' do
    row = create_call_task
    original = row.attributes
    expect do
      statement = <<~SQL.squish
        UPDATE jrc_contact_center_recording_task_links SET task_id = #{row.task_id + 1} WHERE id = #{row.id}
      SQL
      ApplicationRecord.transaction(requires_new: true) { ApplicationRecord.connection.execute(statement) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.attributes).to eq(original)
    expect(native_effect_counts).to eq([1, 1, 1])
  end

  it 'keeps the historic call link while withholding a now-private native Task reference on read' do
    row = create_call_task
    project.project_members.where(account: account, user: actor).sole.destroy!
    page = JrcContactCenter::RecordingTaskList.new(account: account, member: member).call(record.id)
    expect(page.fetch(:items).sole).to include(id: row.id.to_s, request_id: request_id, target: nil)
    expect(page.to_json).not_to include(project.name, input.fetch('task').fetch('title'))
    expect(native_effect_counts).to eq([1, 1, 1])
  end
end
