require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::Approvals do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic pilot company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:higher) { create(:jrc_sd_priority, unit: sd_unit, position: 2) }
  let(:definition) do
    value = JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id],
                                                         'operator_ids' => [sd_account_user.id],
                                                         'priority_order' => { sd_unit.id.to_s => [sd_priority.id, higher.id] })
    value['rules']['R01']['enabled'] = true
    value
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:event) do
    JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket, rule_key: 'R01',
                                     correlation_key: 'R01:synthetic-case', detected_at: Time.current,
                                     evidence: { 'cycle_key' => "service-desk:ticket:#{ticket.id}:cycle:initial" })
  end
  let(:service) { described_class.new(sd_account_user) }
  let(:arguments) { { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.lock_version, 'priority_id' => higher.id } }
  let(:approval) { service.prepare(event_id: event.id, tool: 'update_service_ticket', arguments: arguments) }

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
  end

  it 'uses the existing native executor once and raises the priority exactly one configured level' do
    value = service.approve(id: approval.id, payload_digest: approval.payload_digest)
    expect(value.reload.state).to eq('succeeded')
    expect(ticket.reload.priority_id).to eq(higher.id)
    expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.not_to change(ticket.reload, :lock_version)
    expect(JrcServiceDesk::TicketEvent.where(ticket: ticket, event_type: 'ticket_updated').count).to eq(1)
  end

  it 'returns the same pending approval for the same exact native command' do
    first = approval
    expect { service.prepare(event_id: event.id, tool: 'update_service_ticket', arguments: arguments) }
      .not_to change(JrcNico::Helpdesk::Approval, :count)
    expect(service.prepare(event_id: event.id, tool: 'update_service_ticket', arguments: arguments).id).to eq(first.id)
  end

  it 'rejects a changed payload digest and cannot execute through the ordinary confirm route' do
    value = approval
    expect { service.approve(id: value.id, payload_digest: 'f' * 64) }.to raise_error(ArgumentError)
    operator = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    expect { operator.execute(value.command) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.reload.priority_id).to eq(sd_priority.id)
  end

  it 'binds approval to expiry and rejects the exact expiration boundary' do
    value = approval
    travel_to(value.expires_at, with_usec: true) do
      expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(ArgumentError, /expired/)
    end
    expect(ticket.reload.priority_id).to eq(sd_priority.id)
  end

  it 'revalidates current Unit membership before approval execution' do
    value = approval
    sd_membership.update!(active: false)
    expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ticket.reload.priority_id).to eq(sd_priority.id)
  end

  it 'rejects modified stored command arguments, even with the original valid approval' do
    value = approval
    value.command.update!(arguments: arguments.merge('priority_id' => sd_priority.id))
    expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(ArgumentError, /changed/)
    expect(ticket.reload.priority_id).to eq(sd_priority.id)
  end

  it 'does not execute a foreign ticket or an unrelated tool under a valid rule event' do
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect { service.prepare(event_id: event.id, tool: 'update_service_ticket', arguments: arguments.merge('ticket_id' => foreign.id)) }
      .to raise_error(Pundit::NotAuthorizedError)
    expect { service.prepare(event_id: event.id, tool: 'send_message', arguments: { 'conversation_id' => 1, 'content' => 'No real send' }) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'blocks the account-wide hourly limit before a side effect' do
    definition['hourly_limit'] = 1
    value = approval
    other = JrcNico::Session.create!(account: sd_account, user: create(:user, account: sd_account))
    command = other.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic reservation')
    member = sd_account.account_users.find_by!(user_id: other.user_id)
    JrcNico::Helpdesk::Approval.create!(account: sd_account, event: event, command: command, approver: member,
                                        payload_digest: 'a' * 64, expires_at: 10.minutes.from_now, approved_at: Time.current, state: 'succeeded')
    expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(ArgumentError, /hourly/)
    expect(ticket.reload.priority_id).to eq(sd_priority.id)
  end

  it 'marks an ambiguous failure unknown and prohibits retry or fake reconciliation' do
    value = approval
    native = instance_double(JrcNico::OperatorSession)
    allow(JrcNico::OperatorSession).to receive(:new).and_return(native)
    allow(native).to receive(:execute).and_raise(Timeout::Error, 'Synthetic provider timeout')
    expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(Timeout::Error)
    expect(value.reload.state).to eq('unknown')
    expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to raise_error(ArgumentError, /reconciliation/)
    expect { service.reconcile(id: value.id, resource_type: 'JrcServiceDesk::Ticket', resource_id: ticket.id) }
      .to raise_error(ArgumentError, /evidence/)
  end

  it 'cancels only pending actions and preserves unknown outcomes' do
    value = approval
    expect(service.cancel(id: value.id).state).to eq('cancelled')
    expect(value.command.reload.status).to eq('cancelled')
    expect { service.cancel(id: value.id) }.to raise_error(ArgumentError)
  end

  context 'with an explicit R12 high-priority target' do
    let(:critical_high) { create(:jrc_sd_priority, unit: sd_unit, position: 3) }
    let(:maximum) { create(:jrc_sd_priority, unit: sd_unit, position: 4) }
    let(:definition) do
      value = super()
      value['rules']['R01']['enabled'] = false
      value['rules']['R12'].merge!('enabled' => true, 'critical_company_ids' => [company.id],
                                   'priority_ids' => { sd_unit.id.to_s => critical_high.id })
      value['priority_order'][sd_unit.id.to_s] = [sd_priority.id, higher.id, critical_high.id, maximum.id]
      value
    end
    let(:event) do
      JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket, rule_key: 'R12',
                                       correlation_key: 'R12:synthetic-case', detected_at: Time.current,
                                       evidence: { 'cycle_key' => "service-desk:ticket:#{ticket.id}:cycle:initial" })
    end
    let(:arguments) { { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.lock_version, 'priority_id' => critical_high.id } }

    it 'uses the configured target rather than inferring the next or maximum priority' do
      preview = JrcNico::Helpdesk::ActionPreview.new(context: JrcNico::Helpdesk::Context.new(sd_account_user), event: event)
      expect(preview.priority_arguments).to eq(arguments)
      value = approval
      expect(value.command.arguments['priority_id']).to eq(critical_high.id)
      expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.to change { ticket.reload.priority_id }.to(critical_high.id)
      expect { service.approve(id: value.id, payload_digest: value.payload_digest) }.not_to(change { ticket.reload.lock_version })
    end

    it 'refuses a different, maximum or inactive target before preparing a native command' do
      expect { service.prepare(event_id: event.id, tool: 'update_service_ticket', arguments: arguments.merge('priority_id' => maximum.id)) }
        .to raise_error(ArgumentError, /preview/)
      critical_high.update!(active: false)
      expect { approval }.to raise_error(ArgumentError, /priority/)
      expect(JrcNico::Helpdesk::Approval.where(event: event)).to be_empty
    end
  end
end
