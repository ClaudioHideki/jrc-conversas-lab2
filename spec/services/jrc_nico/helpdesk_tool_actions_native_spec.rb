require 'rails_helper'

RSpec.describe JrcNico::HelpdeskToolActions do
  include_context 'JRC Service Desk domain'

  let(:access) { JrcNico::OperationalAccess.new(account: sd_account, user: sd_user) }
  let(:session) { JrcNico::Session.create!(account: sd_account, user: sd_user) }
  let(:command) { session.commands.create!(request_id: SecureRandom.uuid, message: 'Synthetic internal command') }
  let(:executor) { JrcNico::ToolExecutor.new(access, command: command) }
  let(:ticket) { sd_ticket }

  before { sd_account.update!(custom_attributes: { 'nico_enabled' => true }) }

  it 'creates a real internal task once per command and persists its protected resource manifest' do
    input = { 'ticket_id' => ticket.id, 'title' => 'Synthetic root-cause action plan', 'priority' => 'high',
              'checklist' => [{ 'title' => 'Review authorized evidence', 'done' => false }] }
    result = executor.call('create_service_ticket_task', input)
    expect { executor.call('create_service_ticket_task', input) }.not_to change(JrcServiceDesk::TicketTask, :count)
    task = JrcServiceDesk::TicketTask.find(result[:id])
    expect(task).to have_attributes(account_id: sd_account.id, unit_id: sd_unit.id, ticket_id: ticket.id, visibility: 'internal')
    expect(result[:resources]).to include(['JrcServiceDesk::TicketTask', task.id])
    expect(executor.call('read_service_ticket_tasks', 'ticket_id' => ticket.id)[:items].size).to eq(1)
  end

  it 'does not expose internal task results after native membership revocation' do
    result = executor.call('create_service_ticket_task', 'ticket_id' => ticket.id, 'title' => 'Synthetic internal task')
    sd_membership.update!(active: false)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::TicketTask', result[:id]) }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'creates a native mass incident with authorized children once and revalidates saved output' do
    sd_as_admin!
    other = sd_ticket
    input = { 'unit_id' => sd_unit.id, 'title' => 'Synthetic mass incident', 'severity' => 'high', 'ticket_ids' => [ticket.id, other.id] }
    result = executor.call('create_service_incident', input)
    expect { executor.call('create_service_incident', input) }.not_to change(JrcServiceDesk::Incident, :count)
    incident = JrcServiceDesk::Incident.find(result[:id])
    expect(incident.tickets.pluck(:id).sort).to eq([ticket.id, other.id].sort)
    expect(result[:resources]).to include(['JrcServiceDesk::Incident', incident.id], ['JrcServiceDesk::Ticket', other.id])
    sd_membership.update!(active: false)
    expect { JrcNico::DomainAccess.authorize_resource!(access, 'JrcServiceDesk::Incident', incident.id) }
      .to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rejects a foreign child ticket without an incident or partial link' do
    sd_as_admin!
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    input = { 'unit_id' => sd_unit.id, 'title' => 'Synthetic isolated incident', 'severity' => 'high', 'ticket_ids' => [ticket.id, foreign.id] }
    expect { executor.call('create_service_incident', input) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcServiceDesk::Incident.where(account: sd_account)).to be_empty
    expect(ticket.reload.incident_id).to be_nil
  end

  it 'keeps customer notices and current delegated bot/Flow authority outside new internal tools' do
    notice = JrcNico::Notice.create!(account: sd_account, user: sd_user, event_key: SecureRandom.uuid,
                                     kind: 'attention', body: 'Synthetic customer source')
    command.update!(source_notice: notice)
    expect { executor.call('create_service_ticket_task', 'ticket_id' => ticket.id, 'title' => 'Denied') }
      .to raise_error(Pundit::NotAuthorizedError)
    expect(JrcNico::DelegatedActions::GROUPS.values.flatten & JrcNico::HelpdeskToolCatalog::TOOLS.keys).to be_empty
  end

  it 'validates list IDs, checklists and timestamps before any native dispatch' do
    sd_as_admin!
    expect do
      executor.call('create_service_incident', 'unit_id' => sd_unit.id, 'title' => 'Invalid', 'severity' => 'high',
                                               'ticket_ids' => [ticket.id, ticket.id])
    end
      .to raise_error(ArgumentError)
    expect do
      executor.call('create_service_ticket_task', 'ticket_id' => ticket.id, 'title' => 'Invalid',
                                                  'checklist' => [{ 'title' => 'Item', 'done' => 'false' }])
    end
      .to raise_error(ArgumentError)
    expect { executor.call('create_service_ticket_task', 'ticket_id' => ticket.id, 'title' => 'Invalid', 'due_at' => 'tomorrow') }
      .to raise_error(ArgumentError)
    expect(JrcServiceDesk::TicketTask.where(account: sd_account)).to be_empty
  end
end
