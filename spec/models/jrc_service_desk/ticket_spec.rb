# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::Ticket, type: :model do
  include_context 'JRC Service Desk domain'

  def candidate(overrides = {})
    build(:jrc_sd_ticket, **{ account: sd_account, unit: sd_unit, requester: sd_contact, status: sd_status,
                             priority: sd_priority, created_by_membership: sd_membership }.merge(overrides))
  end

  it 'requires exactly one unit and never creates a default unit' do
    before_count = JrcServiceDesk::Unit.count
    record = candidate(unit: nil)
    expect(record).not_to be_valid
    expect(record.errors[:unit]).to be_present
    expect(JrcServiceDesk::Unit.count).to eq(before_count)
  end

  it 'derives the operator from the unit without another operator column' do
    ticket = sd_ticket
    expect(ticket.operator_company).to eq(sd_operator)
    expect(ticket.operator_company_id).to eq(sd_operator.id)
    expect(described_class.column_names).not_to include('operator_company_id', 'project_id')
  end

  it 'rejects a requester from another Account' do
    record = candidate(requester: create(:contact, account: sd_foreign_account))
    expect(record).not_to be_valid
    expect(record.errors[:requester]).to be_present
  end

  it 'rejects a unit from another Account' do
    expect(candidate(unit: sd_foreign_unit)).not_to be_valid
  end

  { status: :jrc_sd_status, priority: :jrc_sd_priority, category: :jrc_sd_category, queue: :jrc_sd_queue }.each do |name, factory|
    it "rejects #{name} from another unit of the same Account" do
      record = candidate(name => create(factory, unit: sd_other_unit))
      expect(record).not_to be_valid
      expect(record.errors[name]).to be_present
    end
  end

  it 'rejects an assignee membership from another unit' do
    other = create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user)
    record = candidate(assignee_membership: other)
    expect(record).not_to be_valid
    expect(record.errors[:assignee_membership]).to be_present
  end

  it 'rejects an inactive assignee membership' do
    other = create(:jrc_sd_membership, unit: sd_unit, active: false)
    expect(candidate(assignee_membership: other)).not_to be_valid
  end

  it 'rejects a native Team from another Account' do
    record = candidate(team: create(:team, account: sd_foreign_account))
    expect(record).not_to be_valid
  end

  it 'requires the ticket Team to match the selected queue Team' do
    team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
    expect(candidate(queue: queue, team: nil)).not_to be_valid
    expect(candidate(queue: queue, team: team)).to be_valid
  end

  it 'requires a configured active initial status rather than a hardcoded status ID' do
    non_initial = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'resolved')
    expect(candidate(status: non_initial)).not_to be_valid
  end

  it 'rejects ownership moves after creation' do
    ticket = sd_ticket
    expect(ticket.update(unit: sd_other_unit)).to be(false)
    expect(ticket.reload.unit_id).to eq(sd_unit.id)
  end

  it 'supports optional category, queue and unassigned responsible without a fake record' do
    expect(candidate(category: nil, queue: nil, assignee_membership: nil)).to be_valid
  end
end
