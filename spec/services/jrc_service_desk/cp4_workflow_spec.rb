# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'JRC Service Desk CP4 transactional workflows', type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:workflow) { JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context) }
  def create_workflow(key: 'workflow-key', attributes: sd_create_attributes, conversation: nil)
    workflow.call(unit_id: sd_unit.id, attributes: attributes, idempotency_key: key, conversation_id: conversation&.id)
  end

  it 'creates the ticket and native relation in a single transaction, with one creation marker' do
    sd_as_admin!
    conversation = create(:conversation, account: sd_account)
    row = create_workflow(conversation: conversation)
    expect(row.ticket_conversations.pluck(:conversation_id)).to eq([conversation.id])
    expect(row.ticket_events.where(event_type: 'creation_context_recorded').count).to eq(1)
    again = create_workflow(conversation: conversation)
    expect(again.id).to eq(row.id)
    expect(again.ticket_conversations.count).to eq(1)
  end

  it 'does not attach a new relation through a retry with an existing key' do
    sd_as_admin!
    row = create_workflow
    conversation = create(:conversation, account: sd_account)
    expect { create_workflow(conversation: conversation) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(row.ticket_conversations.count).to eq(0)
  end

  it 'rolls back creation if the requested conversation is denied' do
    conversation = create(:conversation, account: sd_foreign_account)
    expect do
      expect { create_workflow(conversation: conversation) }.to raise_error(ActiveRecord::RecordNotFound)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'rolls back the entire create if recording the creation marker fails' do
    allow(JrcServiceDesk::TicketEvent).to receive(:create!).and_call_original
    allow(JrcServiceDesk::TicketEvent).to receive(:create!).with(hash_including(event_type: 'creation_context_recorded')).and_raise(ActiveRecord::StatementInvalid)
    expect do
      expect { create_workflow }.to raise_error(ActiveRecord::StatementInvalid)
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'keeps the CP2 broad transition policy denied while requiring D01 rules for work status' do
    row = sd_ticket
    lc_publish
    working = lc_statuses[:working]
    expect(JrcServiceDesk::TicketPolicy.new(sd_context, row).transition?).to be(false)
    expect(JrcServiceDesk::WorkStatusPolicy.new(sd_context, row).change_work_status?).to be(true)
    result = JrcServiceDesk::ChangeWorkStatusService.new(user_context: sd_context).call(
      ticket_id: row.id, status_id: working.id, expected_lock_version: row.lock_version)
    expect(result.reload.status_id).to eq(working.id)
    expect(result.ticket_events.last.data.values_at('from_status_id', 'to_status_id')).to eq([sd_status.id, working.id])
    expect(result.sla_milestones.count).to eq(0)
  end

  it 'does not duplicate history for a no-op and rejects a stale version' do
    row = sd_ticket
    lc_publish
    command = JrcServiceDesk::ChangeWorkStatusService.new(user_context: sd_context)
    expect { command.call(ticket_id: row.id, status_id: row.status_id, expected_lock_version: row.lock_version) }.not_to change(JrcServiceDesk::TicketEvent, :count)
    row.update!(title: 'new version')
    expect { command.call(ticket_id: row.id, status_id: row.status_id, expected_lock_version: 0) }.to raise_error(ActiveRecord::StaleObjectError)
  end

  it 'rejects an open state of another unit, a disabled state and an out-of-phase target' do
    row = sd_ticket
    lc_publish
    targets = [create(:jrc_sd_status, unit: sd_other_unit),
               create(:jrc_sd_status, unit: sd_unit, initial: false, active: false),
               create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'closed')]
    targets.each do |target|
      expect do
        JrcServiceDesk::ChangeWorkStatusService.new(user_context: sd_context).call(
          ticket_id: row.id, status_id: target.id, expected_lock_version: row.lock_version)
      end.to raise_error { |error| expect([ActiveRecord::RecordNotFound, ArgumentError]).to include(error.class) }
    end
    expect(row.reload.status_id).to eq(sd_status.id)
  end

  it 'denies status changes after membership revocation and to admin outside a granted unit' do
    row = sd_ticket
    sd_as_admin!
    sd_membership.update!(active: false)
    expect(JrcServiceDesk::WorkStatusPolicy.new(sd_context, row).change_work_status?).to be(false)
    expect do
      JrcServiceDesk::ChangeWorkStatusService.new(user_context: sd_context).call(ticket_id: row.id, status_id: row.status_id, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
