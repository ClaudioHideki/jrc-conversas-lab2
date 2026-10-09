# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk screen filters keep native scope', type: :service do
  include_context 'JRC Service Desk domain'

  def filtered(values)
    JrcServiceDesk::TicketQuery.new(user_context: sd_context, parameters: values).collection
  end

  it 'keeps phase totals and the filtered list in the same authorized cohort' do
    waiting = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'waiting')
    closed = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'closed')
    open_ticket = sd_ticket
    waiting_ticket = sd_ticket
    waiting_ticket.update!(status: waiting)
    sd_ticket.update!(status: closed)
    create(:jrc_sd_ticket, unit: sd_other_unit)
    create(:jrc_sd_ticket, unit: sd_foreign_unit)
    filters = { unit_id: sd_unit.id, phase: 'active' }
    result = filtered(filters)
    expect(result[:items].pluck(:id)).to match_array([open_ticket.id, waiting_ticket.id])
    counts = JrcServiceDesk::DashboardService.new(user_context: sd_context).call(parameters: filters)
    expect(counts[:total]).to eq(result[:meta][:total])
    expect(counts[:active]).to eq(2)
    expect(filtered(unit_id: sd_unit.id, phase: 'waiting')[:items].pluck(:id)).to eq([waiting_ticket.id])
  end

  it 'separates personal assignments from visible unassigned tickets without widening scope' do
    mine = sd_ticket(assignee_membership: sd_membership)
    available = sd_ticket
    create(:jrc_sd_ticket, unit: sd_other_unit)
    create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect(filtered(mine: 'true')[:items].pluck(:id)).to eq([mine.id])
    expect(filtered(assignment: 'unassigned')[:items].pluck(:id)).to eq([available.id])
    expect { filtered(mine: 'true', assignment: 'unassigned') }.to raise_error(ArgumentError)
  end

  it 'rejects foreign company and unit filters even with a recognized phase' do
    sd_ticket
    expect { filtered(phase: 'active', operator_company_id: sd_foreign_operator.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect { filtered(assignment: 'unassigned', unit_id: sd_other_unit.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not expose records after membership revocation' do
    sd_ticket
    sd_membership.update!(active: false)
    expect { filtered(assignment: 'unassigned') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'treats operator company and incident owner as distinct board dimensions' do
    sd_as_admin!
    primary = sd_ticket
    other_operator = create(:jrc_sd_operator_company, account: sd_account)
    other_unit = create(:jrc_sd_unit, operator_company: other_operator)
    create(:jrc_sd_membership, unit: other_unit, account_user: sd_account_user)
    other_ticket = create(:jrc_sd_ticket, unit: other_unit)
    # The native task service preserves its own validation and audit contracts.
    first = JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(
      ticket_id: primary.id, attributes: { title: 'Current operator task' }, idempotency_key: SecureRandom.uuid
    )
    JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(
      ticket_id: other_ticket.id, attributes: { title: 'Other operator task' }, idempotency_key: SecureRandom.uuid
    )
    result = JrcServiceDesk::OperationsBoardQuery.new(context: sd_context, parameters: {
      kind: 'tasks', operator_company_id: sd_operator.id
    }).call
    expect(result[:items].pluck(:id).map(&:to_s)).to eq([first.id.to_s])
    expect { JrcServiceDesk::OperationsBoardQuery.new(context: sd_context, parameters: {
      kind: 'tasks', operator_company_id: sd_operator.id, unit_id: other_unit.id
    }).call }.to raise_error(ActiveRecord::RecordNotFound)
    expect { JrcServiceDesk::OperationsBoardQuery.new(context: sd_context, parameters: {
      kind: 'tasks', operator_company_id: sd_foreign_operator.id
    }).call }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
