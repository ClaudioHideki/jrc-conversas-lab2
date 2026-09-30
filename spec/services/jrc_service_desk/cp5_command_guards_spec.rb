# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP5 command-level authorization and audit' do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  def grants(*keys)
    skip 'Native CustomRole extension unavailable' unless defined?(::CustomRole) && sd_account_user.respond_to?(:custom_role)
    role = CustomRole.create!(account: sd_account, name: SecureRandom.hex(6), permissions: keys.flatten.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(custom_role: role)
    role
  end

  it 'does not launder priority changes through edit permission' do
    row = sd_ticket
    priority = create(:jrc_sd_priority, unit: sd_unit)
    grants('module_view', 'tickets_view', 'tickets_edit')
    expect { JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(ticket_id: row.id,
      attributes: { title: 'No partial write', priority_id: priority.id }, expected_lock_version: row.lock_version) }.to raise_error(Pundit::NotAuthorizedError)
    expect(row.reload.title).to eq('Test ticket')
    expect(row.ticket_events).to be_empty
  end

  it 'allows a priority-only change without granting arbitrary edits' do
    row = sd_ticket
    priority = create(:jrc_sd_priority, unit: sd_unit)
    grants('module_view', 'tickets_view', 'priority_change')
    command = JrcServiceDesk::UpdateTicketService.new(user_context: sd_context)
    command.call(ticket_id: row.id, attributes: { priority_id: priority.id }, expected_lock_version: row.lock_version)
    expect(row.reload.priority_id).to eq(priority.id)
    expect(row.ticket_events.last.data['priority_id']).to eq([sd_priority.id, priority.id])
    expect { command.call(ticket_id: row.id, attributes: { title: 'Denied' }, expected_lock_version: row.lock_version) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'requires assign capability when creation carries assignment' do
    target = create(:account_user, account: sd_account)
    create(:jrc_sd_membership, unit: sd_unit, account_user: target)
    grants('module_view', 'tickets_view', 'tickets_create', 'customers_view', 'lookups_view')
    expect do
      expect { JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id,
        attributes: sd_create_attributes.merge(assignee_account_user_id: target.id), idempotency_key: SecureRandom.uuid) }.to raise_error(Pundit::NotAuthorizedError)
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(JrcServiceDesk::Ticket.where(account_id: sd_account.id).count).to eq(0)
  end

  it 'records transfer intent and does not silently share a unit' do
    row = sd_ticket
    target = create(:account_user, account: sd_account)
    create(:jrc_sd_membership, unit: sd_unit, account_user: target)
    grants('module_view', 'tickets_view', 'tickets_transfer')
    JrcServiceDesk::TransferTicketService.new(user_context: sd_context).call(ticket_id: row.id,
      attributes: { assignee_account_user_id: target.id }, expected_lock_version: row.lock_version)
    event = row.ticket_events.last
    expect(event.event_type).to eq('ticket_transferred')
    expect(event.actor_membership_id).to eq(sd_membership.id)
    expect(event.account_id).to eq(sd_account.id)
    expect(event.unit_id).to eq(sd_unit.id)
    expect(row.reload.unit_id).to eq(sd_unit.id)
  end

  it 'checks the exact lifecycle capability even on idempotent replay' do
    lc_publish
    row = sd_ticket
    key = SecureRandom.uuid
    row.reload
    policy = JrcServiceDesk::LifecycleSelector.new(row).applicable
    data = { rule_key: 'resolve', expected_lock_version: row.lock_version, expected_policy_version_id: policy.id }
    role = grants('module_view', 'tickets_view', 'history_view', 'sla_view', 'resolve', 'reopen')
    command = JrcServiceDesk::LifecycleTransitionService.new(user_context: sd_context)
    result = command.call(ticket_id: row.id, attributes: data, idempotency_key: key)
    role.update!(permissions: role.permissions - ['jrc_service_desk_resolve'])
    expect { command.call(ticket_id: row.id, attributes: data, idempotency_key: key) }.to raise_error(Pundit::NotAuthorizedError)
    expect(row.lifecycle_transitions.count).to eq(1)
    expect(row.reload.status_id).to eq(result.to_status_id)
  end

  it 'refuses to assign a ticket to a native role without ticket access' do
    row = sd_ticket
    target = create(:account_user, account: sd_account)
    create(:jrc_sd_membership, unit: sd_unit, account_user: target)
    skip 'Native CustomRole extension unavailable' unless defined?(::CustomRole) && target.respond_to?(:custom_role)
    target.update!(custom_role: CustomRole.create!(account: sd_account, name: 'No ticket access', permissions: ['jrc_service_desk_module_view']))
    expect { JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(ticket_id: row.id,
      attributes: { assignee_account_user_id: target.id }, expected_lock_version: row.lock_version) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(row.reload.assignee_membership).to be_nil
  end
  it 'rechecks conversation capability before a creation replay with an existing link' do
    sd_as_admin!
    conversation = create(:conversation, account: sd_account)
    key = SecureRandom.uuid
    command = JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context)
    first = command.call(unit_id: sd_unit.id, attributes: sd_create_attributes, conversation_id: conversation.id, idempotency_key: key)
    grants('module_view', 'tickets_view', 'tickets_create', 'customers_view', 'lookups_view')
    expect do
      expect { command.call(unit_id: sd_unit.id, attributes: sd_create_attributes,
        conversation_id: conversation.id, idempotency_key: key) }.to raise_error(Pundit::NotAuthorizedError)
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(first.ticket_conversations.count).to eq(1)
    expect(JrcServiceDesk::Ticket.where(account_id: sd_account.id).count).to eq(1)
  end

end
