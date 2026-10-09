require 'rails_helper'

RSpec.describe JrcNico::Helpdesk::Delivery do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic pilot company') }
  let(:ticket) { sd_ticket(company_id: company.id) }
  let(:definition) do
    JrcNico::Helpdesk::Definition.defaults.merge('unit_ids' => [sd_unit.id], 'company_ids' => [company.id], 'operator_ids' => [sd_account_user.id])
  end
  let(:policy) do
    JrcNico::Helpdesk::PolicyVersion.create!(account: sd_account, author: sd_account_user, number: 1, state: 'published', enabled: true,
                                             published_at: Time.current, definition: definition,
                                             digest: JrcNico::Helpdesk::Definition.digest(definition))
  end
  let(:event) do
    JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket, rule_key: 'R01',
                                     correlation_key: 'synthetic-recurrence', detected_at: Time.current)
  end

  before { sd_account.update!(custom_attributes: { 'nico_enabled' => true }) }

  it 'keeps independent receipts and does not repeat confirmed delivery when another channel is unavailable' do
    native = described_class.new(source: event, recipient: sd_account_user, channel: 'nico').call
    email = described_class.new(source: event, recipient: sd_account_user, channel: 'email').call
    whatsapp = described_class.new(source: event, recipient: sd_account_user, channel: 'whatsapp').call
    expect(native).to have_attributes(state: 'delivered')
    expect(email).to have_attributes(state: 'blocked', reason: 'durable_commit_required', delivered_at: nil)
    expect(whatsapp).to have_attributes(state: 'blocked', delivered_at: nil)
    expect { described_class.new(source: event, recipient: sd_account_user, channel: 'nico').call }.not_to change(JrcNico::Notice, :count)
    expect(JrcNico::Helpdesk::DeliveryReceipt.where(source_id: event.id).count).to eq(3)
  end

  it 'never treats an unknown channel receipt as safe to send again' do
    receipt = JrcNico::Helpdesk::DeliveryReceipt.create!(account: sd_account, recipient: sd_account_user,
                                                         source_type: 'event', source_id: event.id, channel: 'whatsapp', state: 'unknown')
    expect(described_class.new(source: event, recipient: sd_account_user, channel: 'whatsapp').call).to eq(receipt)
    expect(receipt.reload.attempted_at).to be_nil
  end

  it 'blocks a revoked native recipient and cannot deliver to another Account' do
    event
    sd_membership.update!(active: false)
    value = described_class.new(source: event, recipient: sd_account_user, channel: 'nico').call
    expect(value).to have_attributes(state: 'blocked', reason: 'recipient_permission_revoked')
    foreign = create(:account_user, account: sd_foreign_account)
    receipts = JrcNico::Helpdesk::DeliveryReceipt.count
    expect { described_class.new(source: event, recipient: foreign, channel: 'nico').call }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcNico::Helpdesk::DeliveryReceipt.count).to eq(receipts)
  end

  it 'records the 18h report once per recipient and pilot scope despite growing backlog and a blocked alternate channel' do
    definition['roles']['thiago'] = [sd_account_user.id]
    definition['daily'].merge!('enabled' => true, 'recipients' => [sd_account_user.id], 'channels' => %w[nico email])
    ticket
    now = Time.utc(2026, 10, 8, 21)
    expect(JrcNico::Helpdesk::DailyReporter.new(policy, now: now - 1.minute).call).to be_empty
    first = JrcNico::Helpdesk::DailyReporter.new(policy, now: now).call.fetch(0)
    expect(first.payload['scheduled_hour']).to eq(18)
    receipts = JrcNico::Helpdesk::DeliveryReceipt.where(account: sd_account, source_type: 'daily_report', source_id: first.id)
    expect(receipts.pluck(:channel, :state)).to contain_exactly(%w[nico delivered], %w[email blocked])
    sd_ticket(company_id: company.id)
    expect { JrcNico::Helpdesk::DailyReporter.new(policy, now: now + 1.hour).call }.not_to change(JrcNico::Notice, :count)
    expect(JrcNico::Helpdesk::DailyReport.where(account: sd_account).count).to eq(1)
    expect(first.reload.payload['ticket_ids']).to eq([ticket.id])
  end

  it 'previews scoped daily data without any receipt, notice or dispatch' do
    ticket
    expect do
      output = JrcNico::Helpdesk::DailyReporter.new(policy).preview(member: sd_account_user)
      expect(output).to include('ticket_ids' => [ticket.id], 'preview' => true, 'persisted' => false, 'scheduled_hour' => 18)
      expect(output['autonomy']).to include('state' => 'sem_dados', 'value' => nil)
    end.not_to change(JrcNico::Helpdesk::DeliveryReceipt, :count)
    expect(JrcNico::Helpdesk::DailyReport.where(account: sd_account)).to be_empty
  end

  it 'does not generate the 18h daily report at 17:59 or while the daily policy is OFF' do
    now = Time.utc(2026, 10, 8, 20, 59)
    expect(JrcNico::Helpdesk::DailyReporter.new(policy, now: now).call).to be_empty
    expect(JrcNico::Helpdesk::DailyReporter.new(policy, now: now + 1.minute).call).to be_empty
    expect(JrcNico::Helpdesk::DailyReport.where(account: sd_account)).to be_empty
  end

  it 'keeps the inactivity anchor unchanged after an automatic NICO note' do
    row = sd_ticket(company_id: company.id, opened_at: 16.days.ago)
    profile = JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row, company: company,
                                                       case_kind: 'defect', defect_key: 'voice.trunk')
    context = JrcNico::Helpdesk::Context.new(sd_account_user)
    before = JrcNico::Helpdesk::Facts.new(context: context, policy: policy, ticket: row, trigger: 'monitor').call
    execute_native_tool('add_service_ticket_note', 'ticket_id' => row.id, 'body' => 'Synthetic automatic alert')
    execute_native_tool('create_service_ticket_task', 'ticket_id' => row.id, 'title' => 'Synthetic automatic task')
    after = JrcNico::Helpdesk::Facts.new(context: context, policy: policy, ticket: row, trigger: 'monitor').call
    expect(after['last_relevant_at']).to eq(before['last_relevant_at'])
    expect(profile.reload.last_relevant_at).to be_nil
    JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(ticket_id: row.id, attributes: { title: 'Human progress task' },
                                                                         idempotency_key: 'nico_123_customer-supplied-similar-prefix')
    progress = JrcNico::Helpdesk::Facts.new(context: context, policy: policy, ticket: row, trigger: 'monitor').call
    expect(Time.iso8601(progress['last_relevant_at'])).to be > Time.iso8601(after['last_relevant_at'])
  end

  def execute_native_tool(tool, arguments)
    session = JrcNico::OperatorSession.new(account: sd_account, user: sd_user)
    command = session.ask(message: 'Synthetic native tool proof', request_id: SecureRandom.uuid,
                          prepared: { 'tool' => tool, 'arguments' => arguments })
    session.execute(command)
  end
end
