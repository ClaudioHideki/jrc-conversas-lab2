require 'rails_helper'
require 'timeout'

# Separate committed PostgreSQL connections are opt-in on the disposable candidate database only.
RSpec.describe JrcNico::Helpdesk::Capture, :sd_concurrency do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic concurrent pilot') }
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

  around do |example|
    if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test?
      example.run
    else
      skip 'Opt-in JRC_SD_CONCURRENCY=1 requires a disposable candidate test database'
    end
  end

  before do
    sd_account.update!(custom_attributes: { 'nico_enabled' => true })
    sd_as_admin!
    policy
    ticket
    allow(JrcNico::Helpdesk::EventJob).to receive(:perform_later)
  end

  def concurrent(&operation)
    raise 'Concurrency fixtures must be committed' if ActiveRecord::Base.connection.transaction_open?

    gate = Queue.new
    outcomes = Queue.new
    workers = Array.new(2) { Thread.new { concurrent_operation(gate, outcomes, operation) } }
    2.times { gate << true }
    Timeout.timeout(30) { workers.each(&:join) }
    Array.new(2) { outcomes.pop }
  ensure
    cleanup_workers(workers)
  end

  def concurrent_operation(gate, outcomes, operation)
    ActiveRecord::Base.connection_pool.with_connection do
      gate.pop
      outcomes << operation.call
    rescue StandardError => e
      outcomes << e
    end
  end

  def cleanup_workers(workers)
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  it 'captures one durable recurrence event for simultaneous retries of the same occurrence' do
    previous = sd_ticket(company_id: company.id)
    [previous, ticket].each do |row|
      JrcNico::Helpdesk::TicketProfile.create!(account: sd_account, unit: sd_unit, ticket: row, company: company,
                                               case_kind: 'defect', defect_key: 'voice.trunk')
    end
    member_id = sd_account_user.id
    ticket_id = ticket.id
    outcomes = concurrent do
      described_class.call(ticket: JrcServiceDesk::Ticket.find(ticket_id), trigger: 'created',
                           origin_key: 'synthetic-concurrent-occurrence', member: AccountUser.find(member_id)).map(&:id)
    end
    expect(outcomes).to all(be_an(Array))
    expect(outcomes.flatten.uniq.size).to eq(1)
    expect(JrcNico::Helpdesk::Event.where(account: sd_account, ticket: ticket, rule_key: 'R01').count).to eq(1)
  end

  it 'serializes simultaneous approvals into one native priority change' do
    event = JrcNico::Helpdesk::Event.create!(account: sd_account, actor: sd_account_user, policy_version: policy, ticket: ticket,
                                             rule_key: 'R01', correlation_key: 'synthetic-concurrent-priority', detected_at: Time.current)
    arguments = { 'ticket_id' => ticket.id, 'expected_lock_version' => ticket.lock_version, 'priority_id' => higher.id }
    approval = JrcNico::Helpdesk::Approvals.new(sd_account_user).prepare(event_id: event.id, tool: 'update_service_ticket', arguments: arguments)
    member_id = sd_account_user.id
    outcomes = concurrent do
      JrcNico::Helpdesk::Approvals.new(AccountUser.find(member_id)).approve(id: approval.id, payload_digest: approval.payload_digest)
    end
    expect(outcomes.grep(JrcNico::Helpdesk::Approval)).not_to be_empty
    expect(outcomes.grep(Exception)).to all(be_an(ArgumentError).and(have_attributes(message: match(/reconciliation/))))
    expect(approval.reload.state).to eq('succeeded')
    expect(ticket.reload.priority_id).to eq(higher.id)
    expect(JrcServiceDesk::TicketEvent.where(ticket: ticket, event_type: 'ticket_updated').count).to eq(1)
  end
end
