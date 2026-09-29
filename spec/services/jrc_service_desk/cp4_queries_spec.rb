# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'JRC Service Desk CP4 queries and real aggregates', type: :service do
  include_context 'JRC Service Desk domain'
  def query(filters = {})
    JrcServiceDesk::TicketQuery.new(user_context: sd_context, parameters: filters).collection
  end
  def dashboard(filters = {})
    JrcServiceDesk::DashboardService.new(user_context: sd_context).call(parameters: filters)
  end

  it 'combines search, status, priority, unit, operator, assignee, queue and source' do
    queue = create(:jrc_sd_queue, unit: sd_unit)
    match = sd_ticket(title: 'Printer 100% needs repair', queue: queue, assignee_membership: sd_membership)
    sd_ticket(title: 'Not included')
    result = query(q: '100%', status_id: sd_status.id, priority_id: sd_priority.id,
                   unit_id: sd_unit.id, operator_company_id: sd_operator.id,
                   assignee_id: sd_account_user.id, queue_id: queue.id, source: 'manual')
    expect(result[:meta][:total]).to eq(1)
    expect(result[:items].pluck(:id)).to eq([match.id])
  end

  it 'uses literal wildcard escaping, supports numeric id search, and clears filters' do
    percent = sd_ticket(title: 'Literal % sign')
    sd_ticket(title: 'Normal ticket')
    expect(query(q: '%')[:items].pluck(:id)).to eq([percent.id])
    expect(query(q: percent.id.to_s)[:items].pluck(:id)).to include(percent.id)
    expect(query[:meta][:total]).to eq(2)
  end

  it 'paginates a stable ordered result and returns the real total' do
    rows = 5.times.map { |i| sd_ticket(title: "Fixture #{i}", created_at: Time.utc(2026, 9, 20) + i.minutes) }
    result = query(sort: 'created_at_asc', page: 2, per_page: 2)
    expect(result[:items].pluck(:id)).to eq(rows[2, 2].map(&:id))
    expect(result[:meta]).to eq(total: 5, page: 2, per_page: 2)
    expect(query(page: 10, per_page: 2)[:items]).to be_empty
  end

  it 'computes personal queue solely from explicit active assignment memberships' do
    mine = sd_ticket(assignee_membership: sd_membership)
    sd_ticket
    expect(query(mine: 'true')[:items].pluck(:id)).to eq([mine.id])
  end

  it 'intersects a supplied broad scope with Pundit instead of trusting a caller' do
    mine = sd_ticket
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    hidden = create(:jrc_sd_ticket, unit: sd_other_unit)
    result = JrcServiceDesk::TicketQuery.new(user_context: sd_context, scope: JrcServiceDesk::Ticket.all).collection
    expect(result[:items].pluck(:id)).to eq([mine.id])
    expect(result[:items].pluck(:id)).not_to include(foreign.id, hidden.id)
  end

  it 'limits catalogues to the grant and requires unit before native lookups' do
    own_queue = create(:jrc_sd_queue, unit: sd_unit)
    create(:jrc_sd_queue, unit: sd_other_unit)
    result = JrcServiceDesk::CatalogQuery.new(user_context: sd_context, resource: 'queues').collection
    expect(result[:items].pluck(:id)).to eq([own_queue.id])
    expect { JrcServiceDesk::CatalogQuery.new(user_context: sd_context, resource: 'assignees') }.to raise_error(ArgumentError)
    result = JrcServiceDesk::CatalogQuery.new(user_context: sd_context, resource: 'assignees', parameters: { unit_id: sd_unit.id }).collection
    expect(result[:items].map(&:account_user_id)).to include(sd_account_user.id)
  end

  it 'queries native contacts from the Account but does not pretend that Contact is an operator' do
    sd_contact
    foreign = create(:contact, account: sd_foreign_account)
    result = JrcServiceDesk::CatalogQuery.new(user_context: sd_context, resource: 'requesters', parameters: { unit_id: sd_unit.id }).collection
    expect(result[:items].map(&:id)).to include(sd_contact.id)
    expect(result[:items].map(&:id)).not_to include(foreign.id)
  end

  it 'proves 27 = 8 + 12 + 7 from persisted test rows and recalculates after a controlled mutation' do
    # Test data setup is NOT an implemented lifecycle transition service.
    # Here 8/12 are two configurable open-phase labels; no implicit phase mapping.
    working = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'open', name: 'In progress fixture')
    resolved = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'resolved', name: 'Resolved fixture')
    open_rows = 8.times.map { sd_ticket }
    12.times { sd_ticket.update!(status: working) }
    7.times { sd_ticket.update!(status: resolved) }
    before = dashboard
    expect(before[:total]).to eq(27)
    expect(before[:by_status].to_h { |v| [v[:id], v[:count]] }).to eq(sd_status.id.to_s => 8, working.id.to_s => 12, resolved.id.to_s => 7)
    expect(before[:phases]).to eq('open' => 20, 'waiting' => 0, 'resolved' => 7, 'closed' => 0, 'cancelled' => 0)
    expect(before[:active]).to eq(20)
    open_rows.first.update!(status: resolved)
    after = dashboard
    expect(after[:total]).to eq(27)
    expect(after[:by_status].to_h { |v| [v[:id], v[:count]] }).to eq(sd_status.id.to_s => 7, working.id.to_s => 12, resolved.id.to_s => 8)
    expect(after[:active]).to eq(19)
    expect(after[:phases].values.sum).to eq(after[:total])
    expect(dashboard(status_id: resolved.id)[:total]).to eq(8)
  end

  it 'separates closed and cancelled from active and preserves arithmetic with combined filters' do
    closed = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'closed')
    cancelled = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'cancelled')
    waiting = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'waiting')
    queue = create(:jrc_sd_queue, unit: sd_unit)
    sd_ticket(queue: queue)
    [closed, cancelled, waiting].each { |status| sd_ticket(queue: queue).update!(status: status) }
    sd_ticket # excluded by queue
    result = dashboard(queue_id: queue.id, unit_id: sd_unit.id, page: 2, per_page: 1)
    expect(result[:total]).to eq(4) # page is not a KPI filter
    expect(result[:active]).to eq(2)
    expect(result[:by_status].sum { |v| v[:count] }).to eq(4)
    expect(result[:unavailable]).to include('sla_breached', 'csat', 'time_series')
  end

  it 'never counts another Account or an ungranted unit for agents' do
    sd_ticket
    create(:jrc_sd_ticket, unit: sd_other_unit)
    create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect(dashboard[:total]).to eq(1)
    sd_membership.update!(active: false)
    expect { dashboard }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'allows zero only after a successful real empty query, and reports an actual UTC generation time' do
    result = dashboard
    expect(result[:total]).to eq(0)
    expect(result[:by_status]).to eq([])
    expect(Time.iso8601(result[:generated_at])).to be_within(2.seconds).of(Time.current)
  end
end
