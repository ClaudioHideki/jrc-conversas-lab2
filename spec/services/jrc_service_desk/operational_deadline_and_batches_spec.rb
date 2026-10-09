# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk operational deadline and reviewed batches' do
  include_context 'JRC Service Desk domain'
  before { sd_as_admin! }

  def publish_deadline(after_due: 0, expected: 0, enabled: true)
    @target ||= create(:account_user, account: sd_account, role: :agent)
    @target_membership ||= create(:jrc_sd_membership, unit: sd_unit, account_user: @target)
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, kind: 'approval_deadline', expected_version: expected, enabled: enabled,
      definition: { 'executor_account_user_id' => sd_account_user.id, 'after_due_seconds' => after_due,
                    'new_due_seconds' => 3600, 'target' => { 'approver_account_user_id' => @target.id }, 'reason' => 'Test-only deadline policy' }
    )
  end

  def approval(ticket = sd_ticket)
    JrcServiceDesk::CreateApprovalService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { title: 'Approve test', due_at: Time.current.iso8601(6), approver_account_user_id: sd_account_user.id },
      idempotency_key: SecureRandom.uuid
    )
  end

  it 'escalates a due pending approval once using the native service and audit' do
    version = publish_deadline
    record = approval
    service = JrcServiceDesk::ApprovalDeadlineExecution.new(user_context: sd_context)
    2.times { service.call(approval_id: record.id) }
    expect(record.reload.approver_membership).to eq(@target_membership)
    expect(record.history.count { |event| event['action'] == 'escalation' }).to eq(1)
    expect(JrcServiceDesk::RuleExecution.where(rule_version: version).count).to eq(1)
    expect(record.ticket.ticket_events.where(event_type: 'approval_escalated').count).to eq(1)
  end

  it 'does not escalate before the explicitly configured grace period' do
    publish_deadline(after_due: 3600)
    record = approval
    JrcServiceDesk::ApprovalDeadlineExecution.new(user_context: sd_context).call(approval_id: record.id)
    expect(record.reload.approver_membership_id).to eq(sd_membership.id)
    expect(JrcServiceDesk::RuleExecution.count).to eq(0)
  end

  it 'does not apply a new policy retroactively to unbound approvals' do
    record = approval
    publish_deadline
    JrcServiceDesk::ApprovalDeadlineExecution.new(user_context: sd_context).call(approval_id: record.id)
    expect(record.reload.deadline_rule_version_id).to be_nil
    expect(JrcServiceDesk::RuleExecution.count).to eq(0)
  end

  it 'honors a later OFF version and does not invent a fallback executor' do
    publish_deadline
    record = approval
    publish_deadline(expected: 1, enabled: false)
    JrcServiceDesk::ApprovalDeadlineExecution.new(user_context: sd_context).call(approval_id: record.id)
    expect(record.reload.history).to be_empty
    expect(JrcServiceDesk::RuleExecution.count).to eq(0)
  end

  it 'blocks deadline execution after executor membership revocation' do
    publish_deadline
    record = approval
    sd_membership.update!(active: false)
    expect { JrcServiceDesk::ApprovalDeadlineExecution.new(user_context: sd_context).call(approval_id: record.id) }.to raise_error(
      ActiveRecord::RecordNotFound
    )
    expect(record.reload.history).to be_empty
  end

  def incident(ticket)
    JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, attributes: { title: 'Test incident', severity: 'normal', ticket_ids: [ticket.id] }, idempotency_key: SecureRandom.uuid
    )
  end

  def batch_service
    JrcServiceDesk::IncidentBatchService.new(user_context: sd_context)
  end

  def request_row(ticket)
    { 'id' => ticket.id, 'lock_version' => ticket.reload.lock_version }
  end

  it 'links reviewed exact tickets atomically and replays the same key without new events' do
    first = sd_ticket
    parent = incident(first)
    second = sd_ticket
    values = { 'action' => 'link', 'tickets' => [request_row(second)] }
    proof = batch_service.preview(unit_id: sd_unit.id, incident_id: parent.id, attributes: values)
    2.times do
      batch_service.call(unit_id: sd_unit.id, incident_id: parent.id, attributes: values, idempotency_key: 'batch-link', receipt: proof[:receipt])
    end
    expect(second.reload.incident_id).to eq(parent.id)
    expect(second.ticket_events.where(event_type: 'incident_linked').count).to eq(1)
    expect(batch_service.readback(unit_id: sd_unit.id, incident_id: parent.id, idempotency_key: 'batch-link')['ticket_ids']).to eq([second.id.to_s])
  end

  it 'rejects a tampered preview without any link or audit effect' do
    parent = incident(sd_ticket)
    second = sd_ticket
    values = { 'action' => 'link', 'tickets' => [request_row(second)] }
    expect { batch_service.call(unit_id: sd_unit.id, incident_id: parent.id, attributes: values, idempotency_key: 'bad-proof', receipt: 'bad') }
      .to raise_error(JrcServiceDesk::PublicationPreviewError)
    expect(second.reload.incident_id).to be_nil
    expect(second.ticket_events).to be_empty
  end

  it 'does not apply a batch if one selected ticket is stale' do
    parent = incident(sd_ticket)
    first = sd_ticket
    second = sd_ticket
    values = { 'action' => 'link', 'tickets' => [request_row(first), request_row(second)] }
    proof = batch_service.preview(unit_id: sd_unit.id, incident_id: parent.id, attributes: values)
    second.update!(title: 'Concurrent edit')
    expect { batch_service.call(unit_id: sd_unit.id, incident_id: parent.id, attributes: values, idempotency_key: 'stale', receipt: proof[:receipt]) }
      .to raise_error(ActiveRecord::StaleObjectError)
    expect(first.reload.incident_id).to be_nil
    expect(second.reload.incident_id).to be_nil
  end

  it 'rejects tickets from another Unit before any batch mutation' do
    parent = incident(sd_ticket)
    other_member = create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user)
    foreign = create(:jrc_sd_ticket, unit: sd_other_unit, requester: sd_contact, created_by_membership: other_member)
    values = { 'action' => 'link', 'tickets' => [request_row(foreign)] }
    expect { batch_service.preview(unit_id: sd_unit.id, incident_id: parent.id, attributes: values) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(foreign.reload.incident_id).to be_nil
  end

  %w[internal public_without_notification].each do |visibility|
    it "persists reviewed #{visibility} progress once with no external notification" do
      ticket = sd_ticket
      parent = incident(ticket)
      values = { 'action' => 'note', 'tickets' => [request_row(ticket)], 'body' => 'Reviewed progress', 'visibility' => visibility }
      proof = batch_service.preview(unit_id: sd_unit.id, incident_id: parent.id, attributes: values)
      receipts = proof[:notes].to_h { |note| [note[:ticket_id], note[:receipt]] }
      2.times do
        batch_service.call(unit_id: sd_unit.id, incident_id: parent.id, attributes: values, idempotency_key: 'progress',
                           receipt: proof[:receipt], note_receipts: receipts)
      end
      expect(ticket.ticket_notes.count).to eq(1)
      expect(ticket.ticket_notes.first.visibility).to eq(visibility)
      expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
      result = batch_service.readback(unit_id: sd_unit.id, incident_id: parent.id, idempotency_key: 'progress')
      expect(result['note_ids']).to eq([ticket.ticket_notes.first.id.to_s])
    end
  end

  it 'invalidates a reviewed batch after revocation without using an administrator fallback' do
    ticket = sd_ticket
    parent = incident(ticket)
    values = { 'action' => 'note', 'tickets' => [request_row(ticket)], 'body' => 'Private progress', 'visibility' => 'internal' }
    proof = batch_service.preview(unit_id: sd_unit.id, incident_id: parent.id, attributes: values)
    sd_account_user.update!(role: :agent)
    expect do
      batch_service.call(unit_id: sd_unit.id, incident_id: parent.id, attributes: values, idempotency_key: 'revoked',
                         receipt: proof[:receipt])
    end
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(ticket.ticket_notes).to be_empty
  end
end
