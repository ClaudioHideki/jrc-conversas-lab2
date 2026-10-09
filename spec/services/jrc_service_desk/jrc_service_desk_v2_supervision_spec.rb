# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  it 'does not broaden an ordinary agent dashboard into supervision' do
    sd_ticket
    result = JrcServiceDesk::DashboardService.new(user_context: sd_context).call
    expect(result[:total]).to eq(1)
    expect(result[:supervision]).to be_nil
    expect(result[:unavailable]).to include('sla_breached', 'time_series', 'csat')
  end

  context 'with scoped aggregates excluding foreign Accounts and units' do
    let(:own) { sd_ticket(assignee_membership: sd_membership) }
    let(:result) { JrcServiceDesk::DashboardService.new(user_context: sd_context).call(parameters: { unit_id: sd_unit.id }) }
    let(:data) { result.fetch(:supervision) }

    before do
      sd_as_admin!
      own
      create(:jrc_sd_ticket, unit: sd_foreign_unit)
      create(:jrc_sd_ticket, unit: sd_other_unit)
      create(:jrc_sd_membership, unit: sd_foreign_unit)
      sd_membership.update!(availability: 'available', capacity: 3)
    end

    it 'computes actual ticket, operator and capacity aggregates' do
      expect(result[:total]).to eq(1)
      expect(data[:by_agent]).to eq([{ id: sd_membership.id.to_s, name: sd_user.name, count: 1 }])
      expect(data[:capacity].map { |row| row[:unit_id] }).to eq([sd_unit.id.to_s])
      expect(data[:capacity].first.values_at(:active_tickets, :capacity)).to eq([1, 3])
      expect(data[:evolution].sum { |row| row[:count] }).to eq(1)
      expect(data[:top_categories].sum { |row| row[:count] }).to eq(1)
      expect(own.reload.assignee_membership_id).to eq(sd_membership.id)
    end

    it 'reports unavailable response observations and the required calendar' do
      expect(data[:sla][:observed_cycles]).to eq(0)
      expect(data[:sla][:first_response_average_seconds]).to be_nil
      expect(data[:availability][:calendar_required]).to be(true)
    end
  end

  it 'recalculates hidden technical task counts after native team revocation' do
    sd_as_admin!
    team = create(:team, account: sd_account)
    member = create(:team_member, team: team, user: sd_user)
    ticket = sd_ticket(team: team)
    JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { title: 'Technical task', visibility: 'technical_team', audience_team_id: team.id },
      idempotency_key: 'technical-task'
    )
    service = JrcServiceDesk::DashboardService.new(user_context: sd_context)
    expect(service.call[:supervision][:tasks][:open]).to eq(1)
    member.destroy!
    expect(service.call[:supervision][:tasks][:open]).to eq(0)
  end

  it 'rotates enabled round robin queues using persisted routing events' do
    sd_membership.update!(availability: 'available', capacity: 5)
    other = create(:jrc_sd_membership, unit: sd_unit, availability: 'available', capacity: 5)
    queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'round_robin')
    service = JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context)
    first = sd_ticket(queue: queue)
    service.call(ticket_id: first.id)
    expect(first.reload.assignee_membership_id).to eq(sd_membership.id)
    first.update!(status: create(:jrc_sd_status, unit: sd_unit, phase: 'closed', initial: false))
    second = sd_ticket(queue: queue)
    service.call(ticket_id: second.id)
    expect(second.reload.assignee_membership_id).to eq(other.id)
    expect(second.ticket_events.last.data['mode']).to eq('round_robin')
  end

  it 'uses real active workload for least load and excludes unavailable operators' do
    sd_membership.update!(availability: 'available', capacity: 5)
    other = create(:jrc_sd_membership, unit: sd_unit, availability: 'available', capacity: 5)
    create(:jrc_sd_membership, unit: sd_unit, availability: 'unavailable', capacity: 5)
    sd_ticket(assignee_membership: sd_membership)
    queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'least_load')
    ticket = sd_ticket(queue: queue)
    JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to eq(other.id)
  end

  it 'claims native priority order before creation order' do
    sd_membership.update!(availability: 'available', capacity: 5)
    older = sd_ticket(priority: create(:jrc_sd_priority, unit: sd_unit, position: 9))
    urgent = sd_ticket(priority: create(:jrc_sd_priority, unit: sd_unit, position: 0))
    service = JrcServiceDesk::ClaimNextService.new(user_context: sd_context)
    expect(service.call(unit_id: sd_unit.id, idempotency_key: 'urgent-claim').id).to eq(urgent.id)
    expect(older.reload.assignee_membership_id).to be_nil
  end
end
