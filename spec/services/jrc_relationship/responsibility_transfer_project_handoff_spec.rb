require 'rails_helper'

RSpec.describe JrcRelationship::ResponsibilityTransfer do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:contact) { create(:contact, account: account) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:project) do
    JrcProjects::Projects::Create.call(account: account, actor: actor, attributes: { name: 'Native delivery', contact_id: contact.id },
                                       idempotency_key: SecureRandom.uuid)
  end
  let(:plan) do
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Delivery plan', project: project)
  end
  let(:inputs) do
    { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => target.id, 'transfer_responsibilities' => true,
      'justification' => 'Native project responsibility settled before CS review', 'request_id' => SecureRandom.uuid }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects') }

  it 'moves CS responsibilities only after the native project handoff and preserves its memberships and the immutable review' do
    plan
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { owner_id: target.id, lock_version: project.lock_version }, correlation_id: 'native-handoff')
    native = project.reload.attributes.deep_dup
    memberships = project.project_members.order(:id).map(&:attributes)
    audits = JrcProjects::AuditEvent.count
    preview = service.preview(inputs)
    proof = preview.fetch('responsibilities').first.fetch('project_handoffs').first
    expect(proof).to include('id' => project.id, 'state' => 'already_destination', 'owner_id' => target.id)
    frozen = JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot.deep_dup
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(target.id))
    expect(project.reload.attributes).to eq(native)
    expect(project.project_members.order(:id).map(&:attributes)).to eq(memberships)
    expect(JrcProjects::AuditEvent.count).to eq(audits)
    expect(JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot).to eq(frozen)
  end

  it 'keeps a completed native project historical while transferring its still-active CS plan' do
    plan
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { status: 'completed', acceptance_notes: 'Synthetic acceptance',
                                                     lock_version: project.lock_version },
                                       correlation_id: 'native-acceptance')
    original = project.reload.attributes.deep_dup
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('project_handoffs').first.fetch('state')).to eq('historical')
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(target.id))
    expect(project.reload.attributes).to eq(original)
  end

  it 'blocks a project that still needs its native owner transfer' do
    plan
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('project_responsibility_requires_native_transfer')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect([assignment.reload.owner_id, plan.reload.owner_id, project.reload.owner_id]).to all(eq(actor.id))
  end

  it 'invalidates a later project change without rewriting the frozen proof' do
    plan
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { owner_id: target.id, lock_version: project.lock_version }, correlation_id: 'native-handoff')
    preview = service.preview(inputs)
    frozen = JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot.deep_dup
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project.reload,
                                       attributes: { name: 'Changed native delivery', lock_version: project.lock_version },
                                       correlation_id: 'native-change')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /responsibilities changed/)
    expect(JrcRelationship::BatchReview.find(preview.fetch('id')).snapshot).to eq(frozen)
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(actor.id))
  end

  it 'requires pending source-owned native tasks to be explicitly reviewed even after project ownership is settled' do
    plan
    task = JrcProjects::Tasks::Create.call(account_user: member, project: project,
                                           attributes: { title: 'Unreviewed delivery', assignee_id: actor.id }, correlation_id: 'native-task')
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { owner_id: target.id, lock_version: project.reload.lock_version },
                                       correlation_id: 'native-handoff')
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('project_tasks_require_native_transfer')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    plan.update!(goals: [{ 'metric' => 'Delivery', 'task_id' => task.id }])
    reviewed = service.preview(inputs.merge('request_id' => SecureRandom.uuid))
    service.approve(reviewed.fetch('id'), digest: reviewed.fetch('digest'))
    expect(service.advance(reviewed.fetch('id')).fetch('state')).to eq('completed')
    expect(task.reload.assignee_id).to eq(target.id)
    expect(project.reload.owner_id).to eq(target.id)
  end

  it 'rejects a project from another customer without moving the plan or project' do
    project
    other = create(:contact, account: account)
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { contact_id: other.id, owner_id: target.id, lock_version: project.lock_version },
                                       correlation_id: 'different-native-customer')
    plan
    preview = service.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('project_customer_context_mismatch')
    expect { service.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(actor.id))
  end

  it 'rolls back CS writes when the destination no longer has native access to its project' do
    plan
    JrcProjects::Projects::Update.call(account: account, actor: actor, project: project,
                                       attributes: { owner_id: target.id, lock_version: project.lock_version }, correlation_id: 'native-handoff')
    preview = service.preview(inputs)
    service.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    account.account_users.find_by!(user: target).update!(role: :agent, jrc_projects_enabled: false)
    expect(JrcOperations::Access.projects(account.account_users.find_by!(user: target))).not_to exist
    expect(service.advance(preview.fetch('id')).fetch('state')).to eq('attention')
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(actor.id))
    expect(project.reload.owner_id).to eq(target.id)
    expect(JrcRelationship::BatchReview.find(preview.fetch('id')).items.pluck(:state)).to eq(['failed'])
  end

  it 'omits frozen project identities and native links for a foreign-account reader' do
    plan
    preview = service.preview(inputs)
    foreign = create(:account)
    foreign.enable_features!('jrc_customer_master', 'jrc_relationship')
    user = create(:user, account: foreign, role: :administrator)
    reader = JrcRelationship::Context.new(foreign.account_users.find_by!(user: user))
    shown = JrcRelationship::ResponsibilityReview.new(reader).for_view(JrcRelationship::BatchReview.find(preview.fetch('id')))
    expect(shown.first).to include('state' => 'unavailable', 'entries' => [])
    expect(shown.to_json).not_to include(project.name, 'project_handoffs', plan.title)
  end
end
