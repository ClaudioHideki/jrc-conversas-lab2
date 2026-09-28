# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260925190100_create_jrc_service_desk_core').to_s

# These tests require PostgreSQL with the CP2 migrations applied, not SQLite or DSL doubles.
RSpec.describe 'Service Desk database constraints', type: :model do
  include_context 'JRC Service Desk domain'

  def raw_clone(model, record, overrides = {})
    attrs = record.attributes.except('id')
    attrs['code'] = "constraint-#{SecureRandom.hex(6)}" if attrs.key?('code')
    attrs['idempotency_key'] = SecureRandom.uuid if attrs.key?('idempotency_key')
    attrs.merge!(overrides.stringify_keys)
    model.transaction(requires_new: true) { model.insert_all!([attrs]) }
  end

  it 'runs with PostgreSQL' do
    expect(ActiveRecord::Base.connection.adapter_name).to eq('PostgreSQL')
  end

  it 'has Account NOT NULL in every operational table' do
    CreateJrcServiceDeskCore::TABLES.each do |suffix|
      column = ActiveRecord::Base.connection.columns("jrc_service_desk_#{suffix}").find { |item| item.name == 'account_id' }
      expect(column.null).to be(false)
    end
  end

  it 'has a NOT NULL unit on tickets and no duplicated operator or Project ID' do
    columns = ActiveRecord::Base.connection.columns('jrc_service_desk_tickets')
    expect(columns.find { |item| item.name == 'unit_id' }.null).to be(false)
    expect(columns.map(&:name)).not_to include('operator_company_id', 'project_id')
  end

  it 'uses composite FKs to native AccountUser and Contact references' do
    membership_keys = ActiveRecord::Base.connection.foreign_keys('jrc_service_desk_unit_memberships')
    ticket_keys = ActiveRecord::Base.connection.foreign_keys('jrc_service_desk_tickets')
    expect(membership_keys.map { |key| [key.to_table, Array(key.column)] }).to include(['account_users', %w[account_id account_user_id]])
    expect(ticket_keys.map { |key| [key.to_table, Array(key.column)] }).to include(['contacts', %w[account_id requester_id]])
  end

  it 'rejects a foreign operator even if model validations are bypassed' do
    expect { raw_clone(JrcServiceDesk::Unit, sd_unit, operator_company_id: sd_foreign_operator.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects foreign AccountUser even if validations are bypassed' do
    foreign = create(:account_user, account: sd_foreign_account)
    expect { raw_clone(JrcServiceDesk::UnitMembership, sd_membership, account_user_id: foreign.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects foreign Account on a ticket at the FK layer' do
    record = sd_ticket
    expect { raw_clone(JrcServiceDesk::Ticket, record, account_id: sd_foreign_account.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects a null ticket unit at the database layer' do
    record = sd_ticket
    expect { raw_clone(JrcServiceDesk::Ticket, record, unit_id: nil) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it 'rejects a requester from another Account at the database layer' do
    record = sd_ticket
    foreign = create(:contact, account: sd_foreign_account)
    expect { raw_clone(JrcServiceDesk::Ticket, record, requester_id: foreign.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects assignee membership from another unit even in the same Account' do
    record = sd_ticket
    target = create(:jrc_sd_membership, unit: sd_other_unit)
    expect { raw_clone(JrcServiceDesk::Ticket, record, assignee_membership_id: target.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects a native Team from another Account at the database layer' do
    record = sd_ticket
    foreign = create(:team, account: sd_foreign_account)
    expect { raw_clone(JrcServiceDesk::Ticket, record, team_id: foreign.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects a status from another unit even if validations are bypassed' do
    record = sd_ticket
    other = create(:jrc_sd_status, unit: sd_other_unit)
    expect { raw_clone(JrcServiceDesk::Ticket, record, status_id: other.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects event/ticket mismatch at the database layer' do
    record = create(:jrc_sd_event, ticket: sd_ticket)
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect { raw_clone(JrcServiceDesk::TicketEvent, record, ticket_id: foreign.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects a public note independently of model validation' do
    record = create(:jrc_sd_note, ticket: sd_ticket)
    expect { raw_clone(JrcServiceDesk::TicketNote, record, visibility: 'public') }.to raise_error(ActiveRecord::StatementInvalid, /jrc_sd_note_internal/)
  end

  it 'rejects duplicate initial active statuses in a unit' do
    original = sd_status
    expect { raw_clone(JrcServiceDesk::TicketStatus, original) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects duplicate memberships independently of validation' do
    expect { raw_clone(JrcServiceDesk::UnitMembership, sd_membership) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rejects a milestone referencing another ticket snapshot in the same unit' do
    one = sd_ticket
    two = sd_ticket
    snapshot = create(:jrc_sd_snapshot, ticket: one)
    milestone = create(:jrc_sd_milestone, sla_snapshot: snapshot)
    expect { raw_clone(JrcServiceDesk::SlaMilestone, milestone, ticket_id: two.id, kind: 'resolution') }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'rejects a deadline without calculation provenance at the database layer' do
    milestone = create(:jrc_sd_milestone, sla_snapshot: create(:jrc_sd_snapshot, ticket: sd_ticket))
    expect do
      raw_clone(JrcServiceDesk::SlaMilestone, milestone, kind: 'resolution', due_at: 1.hour.from_now)
    end.to raise_error(ActiveRecord::StatementInvalid, /jrc_sd_milestone_calculation/)
  end

  it 'refuses destructive rollback when any CP2 operational table contains data' do
    expect { CreateJrcServiceDeskCore.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(JrcServiceDesk::Unit.exists?(sd_unit.id)).to be(true)
  end
end
