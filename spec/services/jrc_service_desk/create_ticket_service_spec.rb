# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::CreateTicketService do
  include_context 'JRC Service Desk domain'
  subject(:service) { described_class.new(user_context: sd_context) }

  def create_command(attributes = sd_create_attributes, unit_id: sd_unit.id, key: 'test-create-key')
    service.call(unit_id: unit_id, attributes: attributes, idempotency_key: key)
  end

  it 'persists a scoped ticket and its audit event in one transaction' do
    ticket = create_command
    expect(ticket.reload).to have_attributes(account_id: sd_account.id, unit_id: sd_unit.id,
                                             created_by_membership_id: sd_membership.id, origin_channel: 'manual')
    expect(ticket.ticket_events.pluck(:event_type)).to eq(['ticket_created'])
    expect(ticket.operator_company_id).to eq(sd_operator.id)
  end

  it 'is idempotent for the same normalized request and key' do
    first = create_command
    second = create_command(sd_create_attributes.transform_keys(&:to_s))
    expect(second.id).to eq(first.id)
    expect(first.ticket_events.count).to eq(1)
  end

  it 'creates, reloads and edits without changing ownership, number or relationships' do
    ticket = create_command
    identity = ticket.reload.attributes.slice('id', 'account_id', 'unit_id', 'requester_id',
                                              'status_id', 'priority_id', 'created_by_membership_id')
    changed = JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { title: 'Persisted edit' }, expected_lock_version: ticket.lock_version
    )
    expect(changed.reload.title).to eq('Persisted edit')
    expect(changed.attributes.slice(*identity.keys)).to eq(identity)
    expect(changed.ticket_events.pluck(:event_type)).to eq(%w[ticket_created ticket_updated])
    replay = create_command
    expect(replay.reload).to have_attributes(id: ticket.id, title: 'Persisted edit')
    expect(JrcServiceDesk::Ticket.where(account_id: sd_account.id, unit_id: sd_unit.id).count).to eq(1)
  end

  it 'rejects creation in another unit for an agent with only its own unit grant' do
    expect do
      create_command(unit_id: sd_other_unit.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Ticket.where(unit_id: sd_other_unit.id)).to be_empty
  end

  it 'refuses reusing an idempotency key with a changed payload' do
    first = create_command
    expect { create_command(sd_create_attributes.merge(title: 'Different')) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(first.reload.title).to eq('Created through CP2 service')
  end

  it 'rolls back the ticket when the history write fails' do
    allow(JrcServiceDesk::TicketEvent).to receive(:create!).and_raise(StandardError, 'audit-write-failed')
    expect do
      expect { create_command }.to raise_error(StandardError, 'audit-write-failed')
    end.not_to change(JrcServiceDesk::Ticket, :count)
  end

  it 'rejects a unit from another Account' do
    expect { create_command(unit_id: sd_foreign_unit.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects an ungranted unit even for administrator' do
    sd_as_admin!
    expect { create_command(unit_id: sd_other_unit.id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a requester from another Account' do
    foreign = create(:contact, account: sd_foreign_account)
    expect { create_command(sd_create_attributes.merge(requester_id: foreign.id)) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects a status from another unit without copying it' do
    foreign = create(:jrc_sd_status, unit: sd_other_unit)
    expect { create_command(sd_create_attributes.merge(status_id: foreign.id)) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  %i[account_id unit_id operator_company_id created_by_membership_id origin_channel status lock_version].each do |key|
    it "rejects ownership/system attribute #{key} supplied as a parameter" do
      expect { create_command(sd_create_attributes.merge(key => 123)) }.to raise_error(ArgumentError)
    end
  end

  it 'does not accept permissive integer coercion for unit identifiers' do
    expect { create_command(unit_id: "#{sd_unit.id}abc") }.to raise_error(ArgumentError)
  end

  it 'does not create a default unit or configuration when required data is missing' do
    count = JrcServiceDesk::Unit.count
    expect { create_command(sd_create_attributes.except(:status_id)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcServiceDesk::Unit.count).to eq(count)
  end
end
