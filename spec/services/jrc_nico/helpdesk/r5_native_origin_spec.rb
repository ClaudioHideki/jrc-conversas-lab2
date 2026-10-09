# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::NativeOrigin do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
  end

  def update_ticket(ticket, title, command: nil)
    JrcServiceDesk::UpdateTicketService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                           attributes: { title: title }, expected_lock_version: ticket.lock_version,
                                                                           execution_command: command)
  end

  it 'records actual human progress and leaves a no-op without a new event' do
    ticket = sd_ticket(opened_at: 16.days.ago)
    update_ticket(ticket, 'Actual native human update')
    event = ticket.ticket_events.where(event_type: 'ticket_updated').last
    expect(event.data['origin']).to include('schema' => 'native-operation-v1', 'kind' => 'operator')
    expect(described_class.new(event).classification).to eq('covered_human')
    count = ticket.ticket_events.count
    update_ticket(ticket.reload, ticket.title)
    expect(ticket.ticket_events.count).to eq(count)
  end

  it 'binds a real approved native NICO Command and successful ticket readback' do
    ticket = sd_ticket
    session = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    arguments = { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.lock_version, 'title' => 'Native NICO update' }
    command = session.ask(message: 'Synthetic approved update', request_id: SecureRandom.uuid,
                          prepared: { 'tool' => 'update_service_ticket', 'arguments' => arguments })
    session.execute(command)
    expect(command.reload.status).to eq('succeeded')
    event = ticket.ticket_events.where(event_type: 'ticket_updated').last
    expect(ticket.reload.title).to eq('Native NICO update')
    expect(event.data['origin']).to include('command_id' => command.id, 'request_id' => command.request_id)
    expect(described_class.new(event).classification).to eq('human_approved_nico')
    expect(described_class.new(event).proven_nico?).to be(true)
  end

  it 'rejects a Hash masquerading as execution authority before changing a native ticket' do
    ticket = sd_ticket
    before = ticket.attributes
    expect { update_ticket(ticket, 'Should not persist', command: { 'autonomous' => true }) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.reload.attributes).to eq(before)
    expect(ticket.ticket_events.where(event_type: 'ticket_updated')).to be_empty
  end

  it 'keeps a caller-supplied NICO-looking prefix on a human note as human progress' do
    ticket = sd_ticket
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                             attributes: { body: 'Real human progress' },
                                                                             idempotency_key: 'nico_999_12345678-1234-4123-8123-123456789abc')
    expect(described_class.new(note)).not_to be_proven_nico
  end

  it 'records native human closure provenance without claiming autonomous authority' do
    ticket = sd_ticket
    lc_snapshot(ticket)
    lc_publish(definition: lc_definition(tracked: true))
    lc_execute(ticket, 'resolve')
    close = lc_execute(ticket, 'close')
    expect(close.payload.dig('sla', 'cycle_id')).to be_present
    expect(described_class.new(close).classification).to eq('covered_human')
  end

  it 'uses actual human update events for R13 and excludes a proven NICO update and a no-op from resetting the anchor' do
    now = Time.utc(2026, 10, 8, 12)
    ticket = sd_ticket(opened_at: now - 16.days)
    policy = JrcNico::Helpdesk::PolicyVersion.new(account: sd_account, definition: JrcNico::Helpdesk::Definition.defaults)
    travel_to(now - 6.days) { update_ticket(ticket, 'Actual earlier human progress') }
    expected = ticket.ticket_events.where(event_type: 'ticket_updated').last.created_at
    travel_to(now) do
      session = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
      arguments = { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.reload.lock_version, 'title' => 'Later approved NICO update' }
      command = session.ask(message: 'Synthetic later NICO progress', request_id: SecureRandom.uuid,
                            prepared: { 'tool' => 'update_service_ticket', 'arguments' => arguments })
      session.execute(command)
      expect(command.reload.status).to eq('succeeded')
      update_ticket(ticket.reload, ticket.title)
      facts = JrcNico::Helpdesk::Facts.new(context: JrcNico::Helpdesk::Context.new(sd_account_user),
                                           policy: policy, ticket: ticket.reload, trigger: 'monitor', now: now).call
      expect(facts).to include('last_relevant_at' => expected.iso8601(6), 'inactive_seconds' => 6.days.to_f)
      rules = policy.definition.deep_dup
      rules['rules']['R13']['enabled'] = true
      expect(JrcNico::Helpdesk::RuleDetector.new(definition: rules, facts: facts).call.first[:evidence]).to include('level' => 2)
    end
  end

  it 'requires current history permission before calculating inactivity' do
    permissions = %w[module_view tickets_view notes_view]
    role = create(:custom_role, account: sd_account, permissions: permissions.map { |key| "jrc_service_desk_#{key}" })
    sd_account_user.update!(role: :agent, custom_role: role)
    ticket = sd_ticket(opened_at: 16.days.ago)
    policy = JrcNico::Helpdesk::PolicyVersion.new(account: sd_account, definition: JrcNico::Helpdesk::Definition.defaults)
    facts = JrcNico::Helpdesk::Facts.new(context: JrcNico::Helpdesk::Context.new(sd_account_user), policy: policy,
                                         ticket: ticket, trigger: 'monitor').call
    expect(facts).to include('activity_coverage' => 'history_permission_required')
    expect(facts).not_to have_key('inactive_seconds')
    rules = policy.definition.deep_dup
    rules['rules']['R13']['enabled'] = true
    expect(JrcNico::Helpdesk::RuleDetector.new(definition: rules, facts: facts).call).to be_empty
  end
end
