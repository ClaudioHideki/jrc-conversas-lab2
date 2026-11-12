require 'rails_helper'

RSpec.describe JrcRelationship::NativeResponsibilities do
  include_context 'JRC Service Desk domain'
  let(:target) { create(:user, account: sd_account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, owner: sd_user, contact: sd_contact) }
  let(:plan) { JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: assignment, owner: sd_user, title: 'Native pending follow-up') }
  let(:reviews) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:inputs) do
    { 'ids' => [assignment.id], 'operation' => 'assign', 'owner_id' => target.id, 'transfer_responsibilities' => true,
      'justification' => 'Synthetic native pending responsibility handoff', 'request_id' => SecureRandom.uuid }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
  end

  it 'freezes a pending ticket and transfers it through the native service and history' do
    ticket = sd_ticket(assignee_membership: sd_membership)
    destination = create(:jrc_sd_membership, unit: sd_unit, account_user: sd_account.account_users.find_by!(user: target))
    plan.update!(goals: [{ 'metric' => 'Resolution', 'ticket_id' => ticket.id }])
    preview = reviews.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('entries')).to include(include('kind' => 'service_tickets', 'id' => ticket.id))
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    reviews.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(reviews.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect(ticket.reload.assignee_membership_id).to eq(destination.id)
    expect(JrcServiceDesk::TicketEvent.where(ticket: ticket, event_type: 'ticket_assigned')).to exist
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(target.id))
    expect(reviews.advance(preview.fetch('id')).fetch('state')).to eq('completed')
  end

  it 'rolls back the portfolio and plan when destination unit assignment eligibility is revoked' do
    ticket = sd_ticket(assignee_membership: sd_membership)
    destination = create(:jrc_sd_membership, unit: sd_unit, account_user: sd_account.account_users.find_by!(user: target))
    plan.update!(goals: [{ 'metric' => 'Resolution', 'ticket_id' => ticket.id }])
    preview = reviews.preview(inputs)
    reviews.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    destination.update!(manual_assignment_enabled: false)
    expect(reviews.advance(preview.fetch('id')).fetch('state')).to eq('attention')
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(sd_user.id))
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(JrcServiceDesk::TicketEvent.where(ticket: ticket, event_type: 'ticket_assigned')).not_to exist
  end

  it 'transfers an explicitly referenced pending task without changing project ownership or membership' do
    sd_account.account_users.find_by!(user: target).update!(role: :agent, jrc_projects_enabled: true)
    attributes = { name: 'Synthetic project source', contact_id: sd_contact.id }
    project = JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user, attributes: attributes, idempotency_key: SecureRandom.uuid)
    JrcProjects::ProjectMember.create!(account: sd_account, project: project, user: target, role: 'member')
    task = JrcProjects::Tasks::Create.call(account_user: sd_account_user, project: project,
                                           attributes: { title: 'Synthetic native task', assignee_id: sd_user.id }, correlation_id: 'test-create')
    original_members = project.project_members.order(:id).map(&:attributes)
    plan.update!(goals: [{ 'metric' => 'Delivery', 'task_id' => task.id }])
    preview = reviews.preview(inputs)
    reviews.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect(reviews.advance(preview.fetch('id')).fetch('state')).to eq('completed')
    expect(task.reload).to have_attributes(assignee_id: target.id, created_by_id: sd_user.id)
    expect(project.reload.owner_id).to eq(sd_user.id)
    expect(project.project_members.order(:id).map(&:attributes)).to eq(original_members)
    expect(JrcProjects::AuditEvent.where(auditable_type: task.class.name, auditable_id: task.id, action: 'projects.task.updated')).to exist
  end

  it 'rolls back native writes when an otherwise valid destination has no eligible Service Desk unit membership' do
    target
    ticket = sd_ticket(assignee_membership: sd_membership)
    plan.update!(goals: [{ 'metric' => 'Resolution', 'ticket_id' => ticket.id }])
    preview = reviews.preview(inputs)
    reviews.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect { reviews.advance(preview.fetch('id')) }.to raise_error(ActiveRecord::RecordNotFound)
    expect([assignment.reload.owner_id, plan.reload.owner_id]).to all(eq(sd_user.id))
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(JrcServiceDesk::TicketEvent.where(ticket: ticket, event_type: 'ticket_assigned')).not_to exist
  end

  it 'does not promote a project viewer to receive a pending task and rolls back the whole customer' do
    sd_account.account_users.find_by!(user: target).update!(role: :agent, jrc_projects_enabled: true)
    attributes = { name: 'Synthetic viewer project', contact_id: sd_contact.id }
    project = JrcProjects::Projects::Create.call(account: sd_account, actor: sd_user, attributes: attributes, idempotency_key: SecureRandom.uuid)
    member = JrcProjects::ProjectMember.create!(account: sd_account, project: project, user: target, role: 'viewer')
    task = JrcProjects::Tasks::Create.call(account_user: sd_account_user, project: project,
                                           attributes: { title: 'Synthetic protected task', assignee_id: sd_user.id }, correlation_id: 'test-create')
    plan.update!(goals: [{ 'metric' => 'Delivery', 'task_id' => task.id }])
    preview = reviews.preview(inputs)
    reviews.approve(preview.fetch('id'), digest: preview.fetch('digest'))
    expect { reviews.advance(preview.fetch('id')) }.to raise_error(Pundit::NotAuthorizedError)
    expect([assignment.reload.owner_id, plan.reload.owner_id, task.reload.assignee_id]).to all(eq(sd_user.id))
    expect(member.reload.role).to eq('viewer')
    expect(JrcProjects::AuditEvent.where(auditable_type: task.class.name, auditable_id: task.id, action: 'projects.task.updated')).not_to exist
  end

  it 'uses executor eligibility when an authorized origin reader has no operational Service Desk membership' do
    ticket = sd_ticket(assignee_membership: sd_membership)
    plan.update!(goals: [{ 'metric' => 'Resolution', 'ticket_id' => ticket.id }])
    preview = reviews.preview(inputs)
    reader = create(:user, account: sd_account, role: :administrator)
    member = sd_account.account_users.find_by!(user: reader)
    before = JrcServiceDesk::UnitMembership.where(account_user: member).count
    source = JrcRelationship::ResponsibilityReview.new(JrcRelationship::Context.new(member))
    review = JrcRelationship::BatchReview.find(preview.fetch('id'))
    expect { source.verify!(review, lock: false) }.not_to raise_error
    expect(source.for_view(review).first.fetch('state')).to eq('ready')
    expect(JrcServiceDesk::UnitMembership.where(account_user: member).count).to eq(before)
  end

  it 'blocks a ticket shared by plans for different customers rather than silently transferring its source' do
    ticket = sd_ticket(assignee_membership: sd_membership)
    plan.update!(goals: [{ 'metric' => 'Resolution', 'ticket_id' => ticket.id }])
    other = JrcRelationship::Assignment.create!(account: sd_account, owner: sd_user, contact: create(:contact, account: sd_account))
    JrcRelationship::SuccessPlan.create!(account: sd_account, assignment: other, owner: sd_user, title: 'Other customer plan',
                                         goals: [{ 'metric' => 'Shared source', 'ticket_id' => ticket.id }])
    preview = reviews.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('shared_native_responsibility_requires_review')
    expect { reviews.approve(preview.fetch('id'), digest: preview.fetch('digest')) }.to raise_error(ArgumentError, /native source review/)
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
  end

  it 'blocks a visible ticket for another customer and denies a foreign-account reference without leaking its details' do
    ticket = sd_ticket(requester: create(:contact, account: sd_account), assignee_membership: sd_membership)
    plan.update!(goals: [{ 'metric' => 'Wrong customer', 'ticket_id' => ticket.id }])
    preview = reviews.preview(inputs)
    expect(preview.fetch('responsibilities').first.fetch('blockers')).to include('native_customer_context_mismatch')
    foreign = create(:jrc_sd_ticket)
    plan.update!(goals: [{ 'metric' => 'Foreign source', 'ticket_id' => foreign.id }])
    expect { reviews.preview(inputs.merge('request_id' => SecureRandom.uuid)) }.to raise_error(Pundit::NotAuthorizedError)
    expect(foreign.reload.assignee_membership_id).to be_nil
  end
end
