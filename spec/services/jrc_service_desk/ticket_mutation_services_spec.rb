# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk updates and assignment' do
  include_context 'JRC Service Desk domain'
  let(:ticket) { sd_ticket }
  let(:update_service) { JrcServiceDesk::UpdateTicketService.new(user_context: sd_context) }
  let(:assign_service) { JrcServiceDesk::AssignTicketService.new(user_context: sd_context) }

  it 'persists updates, increments the version and records before/after values' do
    changed = update_service.call(ticket_id: ticket.id, attributes: { title: 'Changed' }, expected_lock_version: ticket.lock_version)
    expect(changed.reload.title).to eq('Changed')
    expect(changed.lock_version).to eq(1)
    expect(changed.ticket_events.last.data['title']).to eq(['Test ticket', 'Changed'])
  end

  it 'rejects stale updates instead of overwriting another change' do
    old_version = ticket.lock_version
    update_service.call(ticket_id: ticket.id, attributes: { title: 'First update' }, expected_lock_version: old_version)
    expect do
      update_service.call(ticket_id: ticket.id, attributes: { title: 'Stale update' }, expected_lock_version: old_version)
    end.to raise_error(ActiveRecord::StaleObjectError)
    expect(ticket.reload.title).to eq('First update')
  end

  it 'does not expose status workflow transitions through the generic update' do
    expect do
      update_service.call(ticket_id: ticket.id, attributes: { status_id: sd_status.id }, expected_lock_version: 0)
    end.to raise_error(ArgumentError)
  end

  it 'rejects priority from another unit' do
    other = create(:jrc_sd_priority, unit: sd_other_unit)
    expect do
      update_service.call(ticket_id: ticket.id, attributes: { priority_id: other.id }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'assigns only to an active AccountUser/unit membership' do
    target = create(:jrc_sd_membership, unit: sd_unit)
    result = assign_service.call(ticket_id: ticket.id, attributes: { assignee_account_user_id: target.account_user_id }, expected_lock_version: 0)
    expect(result.reload.assignee_membership_id).to eq(target.id)
    expect(result.ticket_events.last.event_type).to eq('ticket_assigned')
  end

  it 'rejects assignment to another Account' do
    target = create(:account_user, account: sd_foreign_account)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { assignee_account_user_id: target.id }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects assignment to a different unit even if the acting administrator has both grants' do
    sd_as_admin!
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user)
    target = create(:jrc_sd_membership, unit: sd_other_unit)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { assignee_account_user_id: target.account_user_id }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects an inactive target grant' do
    target = create(:jrc_sd_membership, unit: sd_unit, active: false)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { assignee_account_user_id: target.account_user_id }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects native TeamMember as a substitute for a missing unit grant' do
    team = create(:team, account: sd_account)
    target = create(:account_user, account: sd_account)
    create(:team_member, team: team, user: target.user)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { assignee_account_user_id: target.id, team_id: team.id }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'derives a queue Team and never selects a queue from another unit' do
    team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
    result = assign_service.call(ticket_id: ticket.id, attributes: { queue_id: queue.id }, expected_lock_version: 0)
    expect(result.reload.team_id).to eq(team.id)
    other = create(:jrc_sd_queue, unit: sd_other_unit)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { queue_id: other.id }, expected_lock_version: result.lock_version)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a foreign Team and direct membership-ID injection' do
    foreign_team = create(:team, account: sd_foreign_account)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { team_id: foreign_team.id }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect do
      assign_service.call(ticket_id: ticket.id, attributes: { assignee_membership_id: sd_membership.id }, expected_lock_version: 0)
    end.to raise_error(ArgumentError)
  end

  it 'cannot mutate a ticket from another Account by guessing its ID' do
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect do
      update_service.call(ticket_id: foreign.id, attributes: { title: 'Attempt' }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'cannot mutate a ticket from a unit with no grant' do
    other = create(:jrc_sd_ticket, unit: sd_other_unit)
    expect do
      update_service.call(ticket_id: other.id, attributes: { title: 'Attempt' }, expected_lock_version: 0)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
