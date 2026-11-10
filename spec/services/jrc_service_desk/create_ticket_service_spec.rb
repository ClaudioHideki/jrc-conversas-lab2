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

  it 'allows native administrator creation in another configured unit without an operational grant' do
    sd_as_admin!
    status = create(:jrc_sd_status, unit: sd_other_unit)
    priority = create(:jrc_sd_priority, unit: sd_other_unit)
    ticket = create_command(sd_create_attributes.merge(status_id: status.id, priority_id: priority.id), unit_id: sd_other_unit.id)
    expect(ticket.reload.unit_id).to eq(sd_other_unit.id)
    expect(ticket.created_by_membership).to have_attributes(administrative_actor: true, active: false, account_user_id: sd_account_user.id)
    expect(JrcServiceDesk::UnitMembership.operational.where(unit: sd_other_unit, account_user: sd_account_user)).to be_empty
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

  context 'with a configured company destination' do
    let(:company) { sd_account.master_companies.create!(name: 'Synthetic internal customer') }
    let(:recipient) { create(:user, account: sd_account) }
    let(:recipient_membership) do
      create(:jrc_sd_membership, unit: sd_unit, account_user: sd_account.account_users.find_by!(user: recipient),
        availability: 'unavailable', capacity: nil, manual_assignment_enabled: true)
    end
    let(:queue) { create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'manual') }

    before do
      sd_as_admin!
      sd_account.enable_features!('jrc_customer_master')
      sd_contact.update!(company_id: company.id)
      JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user,
        values: { 'company_routes' => [{ 'company_id' => company.id, 'queue_id' => queue.id,
                                       'assignee_account_user_id' => recipient_membership.account_user_id }] },
        expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
      sd_account_user.update!(role: :agent)
    end

    it 'lets an internal agent create a ticket for the customer and assigns the fixed recipient offline' do
      ticket = create_command(sd_create_attributes.merge(company_id: company.id))
      expect(ticket).to have_attributes(assignee_membership_id: recipient_membership.id, queue_id: queue.id,
                                       created_by_membership_id: sd_membership.id, origin_channel: 'manual')
    end

    it 'replays the original ticket after configuration changes without reassigning it' do
      ticket = create_command
      sd_as_admin!
      JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: {},
        expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
      sd_account_user.update!(role: :agent)
      expect(create_command.id).to eq(ticket.id)
      expect(ticket.reload.assignee_membership_id).to eq(recipient_membership.id)
    end

    it 'preserves an explicit destination chosen by the internal agent' do
      other_queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'manual')
      ticket = create_command(sd_create_attributes.merge(queue_id: other_queue.id, assignee_account_user_id: sd_account_user.id))
      expect(ticket).to have_attributes(queue_id: other_queue.id, assignee_membership_id: sd_membership.id)
    end

    it 'does not apply the portal default or another customer route to an unrelated company' do
      sd_as_admin!
      configuration = JrcServiceDesk::PortalRoutingConfiguration.read(sd_unit).merge(
        'queue_id' => queue.id, 'assignee_account_user_id' => recipient_membership.account_user_id)
      JrcServiceDesk::PortalRoutingConfiguration.save!(unit: sd_unit, actor: sd_account_user, values: configuration,
        expected_revision: JrcServiceDesk::PortalRoutingConfiguration.revision(sd_unit))
      sd_account_user.update!(role: :agent)
      sd_contact.update!(company_id: nil)
      ticket = create_command
      expect(ticket.queue_id).to be_nil
      expect(ticket.assignee_membership_id).to be_nil
    end
  end

  it 'does not create a default unit or configuration when required data is missing' do
    count = JrcServiceDesk::Unit.count
    expect { create_command(sd_create_attributes.except(:status_id)) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcServiceDesk::Unit.count).to eq(count)
  end
end
