# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::TaskProgression, type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:ticket) { sd_ticket }
  let(:tasks) { JrcServiceDesk::CreateTaskService.new(user_context: sd_context) }
  let(:updates) { JrcServiceDesk::UpdateTaskService.new(user_context: sd_context) }
  let(:approvals) { JrcServiceDesk::CreateApprovalService.new(user_context: sd_context) }

  it 'prevents completion until its authorized subtasks are completed, without replacing task identities' do
    parent = tasks.call(ticket_id: ticket.id, attributes: { title: 'Restore' }, idempotency_key: 'parent')
    child = tasks.call(ticket_id: ticket.id, attributes: { title: 'Verify', parent_task_id: parent.id }, idempotency_key: 'child')
    expect { updates.call(ticket_id: ticket.id, task_id: parent.id, attributes: { status: 'completed' }, expected_lock_version: parent.lock_version) }
      .to raise_error(ActiveRecord::RecordInvalid)
    updates.call(ticket_id: ticket.id, task_id: child.id, attributes: { status: 'completed' }, expected_lock_version: child.lock_version)
    updates.call(ticket_id: ticket.id, task_id: parent.id, attributes: { status: 'completed' }, expected_lock_version: parent.lock_version)
    expect(parent.reload.status).to eq('completed')
    expect(child.reload.parent_task_id).to eq(parent.id)
  end

  it 'rejects a task parent from another ticket and leaves no partial child or event' do
    parent = tasks.call(ticket_id: ticket.id, attributes: { title: 'Restore' }, idempotency_key: 'parent')
    other = sd_ticket
    expect { tasks.call(ticket_id: other.id, attributes: { title: 'Bad child', parent_task_id: parent.id }, idempotency_key: 'bad-child') }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(other.ticket_tasks).to be_empty
  end

  it 'executes one native next task under a published completion policy and blocks replay mutations' do
    policy = lc_publish
    sd_as_admin!
    values = { enabled: true, lifecycle_policy_version_id: policy.current_version_id, lifecycle_policy_digest: policy.current_version.digest,
               next_task: { title: 'Verify customer restoration' }, approval: nil, transition: nil }
    row = tasks.call(ticket_id: ticket.id, attributes: { title: 'Restore', completion_policy: values }, idempotency_key: 'progression')
    updates.call(ticket_id: ticket.id, task_id: row.id, attributes: { status: 'completed' }, expected_lock_version: row.lock_version)
    expect(ticket.ticket_tasks.pluck(:title)).to contain_exactly('Restore', 'Verify customer restoration')
    expect do
      updates.call(ticket_id: ticket.id, task_id: row.id, attributes: { status: 'completed' }, expected_lock_version: row.reload.lock_version)
    end
      .to raise_error(ArgumentError)
    expect(ticket.ticket_tasks.count).to eq(2)
  end

  it 'rolls back completion if the published progression version is revoked before execution' do
    policy = lc_publish
    sd_as_admin!
    values = { enabled: true, lifecycle_policy_version_id: policy.current_version_id, lifecycle_policy_digest: policy.current_version.digest,
               next_task: { title: 'Should not be created' }, approval: nil, transition: nil }
    row = tasks.call(ticket_id: ticket.id, attributes: { title: 'Restore', completion_policy: values }, idempotency_key: 'revoked')
    policy.update!(enabled: false)
    expect { updates.call(ticket_id: ticket.id, task_id: row.id, attributes: { status: 'completed' }, expected_lock_version: row.lock_version) }
      .to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(row.reload.status).to eq('open')
    expect(ticket.ticket_tasks.count).to eq(1)
  end

  it 'allows a current native team approver, then immediately denies that approver after team revocation' do
    sd_as_admin!
    team = create(:team, account: sd_account)
    member = create(:team_member, team: team, user: sd_user)
    row = approvals.call(ticket_id: ticket.id, attributes: { title: 'Approve change', approver_team_id: team.id,
                                                             due_at: 1.day.from_now.iso8601 }, idempotency_key: 'team-approval')
    expect(JrcServiceDesk::TicketApprovalPolicy.new(sd_context, row).decide?).to be(true)
    member.destroy!
    expect(JrcServiceDesk::TicketApprovalPolicy.new(sd_context, row).decide?).to be(false)
    expect(row.reload.status).to eq('pending')
  end

  it 'does not give an administrator implicit approval over an agent-role request' do
    row = approvals.call(ticket_id: ticket.id, attributes: { title: 'Approve access', approver_role: 'agent',
                                                             due_at: 1.day.from_now.iso8601 }, idempotency_key: 'role-approval')
    expect(JrcServiceDesk::TicketApprovalPolicy.new(sd_context, row).decide?).to be(true)
    sd_as_admin!
    expect(JrcServiceDesk::TicketApprovalPolicy.new(sd_context, row).decide?).to be(false)
  end

  it 'rejects a target with no current unit approver and rejects multiple target selectors' do
    expect do
      approvals.call(ticket_id: ticket.id, attributes: { title: 'Bad', approver_role: 'administrator',
                                                         due_at: 1.day.from_now.iso8601 }, idempotency_key: 'empty-role')
    end.to raise_error(Pundit::NotAuthorizedError)
    expect do
      approvals.call(ticket_id: ticket.id, attributes: { title: 'Bad', approver_role: 'agent', approver_account_user_id: sd_account_user.id,
                                                         due_at: 1.day.from_now.iso8601 }, idempotency_key: 'multiple-targets')
    end.to raise_error(ArgumentError)
    expect(ticket.ticket_approvals).to be_empty
  end

  it 'audits escalation and decision without allowing previous history to be erased' do
    row = approvals.call(ticket_id: ticket.id, attributes: { title: 'Approve access', approver_account_user_id: sd_account_user.id,
                                                             due_at: 1.day.from_now.iso8601 }, idempotency_key: 'escalation')
    service = JrcServiceDesk::EscalateApprovalService.new(user_context: sd_context)
    service.call(ticket_id: ticket.id, approval_id: row.id,
                 attributes: { approver_role: 'agent', reason: 'Team handover', due_at: 2.days.from_now.iso8601 },
                 expected_lock_version: row.lock_version)
    expect(row.reload.history.first['action']).to eq('escalation')
    JrcServiceDesk::DecideApprovalService.new(user_context: sd_context).call(
      ticket_id: ticket.id, approval_id: row.id, attributes: { status: 'approved', comment: 'Verified' }, expected_lock_version: row.lock_version
    )
    expect(row.reload.history.map { |entry| entry['action'] }).to eq(%w[escalation decision])
    expect(row.decided_by_membership_id).to eq(sd_membership.id)
    expect { row.update!(history: []) }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
