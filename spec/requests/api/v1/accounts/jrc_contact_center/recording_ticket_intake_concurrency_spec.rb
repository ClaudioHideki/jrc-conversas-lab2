# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

# Actual committed native Ticket/events, separate PostgreSQL backends and account locks.
RSpec.describe 'Native manual recording Ticket transaction contention', :pabx do
  self.use_transactional_tests = false
  include_context 'with native manual recording ticket intake'

  let(:state) { { ready: Queue.new, results: Queue.new } }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable recording Ticket database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  def create_ticket
    input = ticket_input
    described_writer.call(recording_id: input.fetch('recording_id'), unit_id: input.fetch('unit_id'),
                           attributes: input.fetch('ticket'), idempotency_key: ticket_key)
  end

  def described_writer
    JrcContactCenter::RecordingTicketIntake.new(account: account, member: member)
  end

  def ticket_worker
    values = ticket_input.deep_dup
    ids = [account.id, member.id]
    key = ticket_key
    ready, results = state.values_at(:ready, :results)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        ready << connection.raw_connection.backend_pid
        writer = JrcContactCenter::RecordingTicketIntake.new(account: Account.find(ids[0]), member: AccountUser.find(ids[1]))
        results << writer.call(recording_id: values.fetch('recording_id'), unit_id: values.fetch('unit_id'),
                                 attributes: values.fetch('ticket'), idempotency_key: key)
      end
    rescue StandardError => e
      results << e
    end
  end

  def wait_for_ticket_lock
    pid = Timeout.timeout(8) { state[:ready].pop }
    query = <<~SQL.squish
      WITH RECURSIVE blockers(pid) AS (
        SELECT unnest(pg_blocking_pids(#{Integer(pid)})) UNION
        SELECT next_blocker.pid FROM blockers
          CROSS JOIN LATERAL unnest(pg_blocking_pids(blockers.pid)) AS next_blocker(pid)
          WHERE blockers.pid <> pg_backend_pid() AND blockers.pid > 0
      ) SELECT EXISTS (SELECT 1 FROM blockers WHERE pid = pg_backend_pid())
    SQL
    Timeout.timeout(8) { sleep 0.02 until ApplicationRecord.connection.select_value(query) == true }
    pid
  end

  def join_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Owned native Ticket contender remained active' if worker.alive?
    end
  end

  it 'proves two actual waiting backends and commits only one native Ticket and immutable origin' do
    ticket_input
    workers = []
    pids = []
    begin
      account.with_lock do
        2.times do
          workers << ticket_worker
          pids << wait_for_ticket_lock
        end
      end
    ensure
      join_workers(workers)
    end
    results = Array.new(2) { Timeout.timeout(8) { state[:results].pop } }
    expect(pids.uniq.length).to eq(2)
    expect(results).to all(be_a(JrcServiceDesk::Ticket))
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(JrcServiceDesk::Ticket.where(account: account).count).to eq(1)
    expect(JrcServiceDesk::TicketEvent.where(account: account, event_type: 'creation_context_recorded').count).to eq(1)
  end

  it 'rechecks current Service Desk creation authority after waiting on the real source account lock' do
    ticket_input
    workers = []
    begin
      account.with_lock do
        workers << ticket_worker
        wait_for_ticket_lock
        role.update!(permissions: role.permissions - ['jrc_service_desk_tickets_create'])
      end
    ensure
      join_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
  end

  it 'rolls back the real Ticket and events after origin persistence fails and accepts one explicit identical retry' do
    ticket_input
    connection = ApplicationRecord.connection
    name = "cc_synthetic_ticket_origin_#{Integer(account.id)}"
    begin
      condition = "event_type <> 'creation_context_recorded' OR account_id <> #{Integer(account.id)}"
      connection.add_check_constraint(JrcServiceDesk::TicketEvent.table_name, condition, name: name)
      installed = true
      expect { create_ticket }.to raise_error(ActiveRecord::StatementInvalid)
      expect(JrcServiceDesk::Ticket.where(account: account)).to be_empty
      expect(JrcServiceDesk::TicketEvent.where(account: account)).to be_empty
    ensure
      connection.remove_check_constraint(JrcServiceDesk::TicketEvent.table_name, name: name) if installed
    end
    first = create_ticket
    expect(create_ticket.id).to eq(first.id)
    expect(JrcServiceDesk::Ticket.where(account: account).pluck(:id)).to eq([first.id])
  end
end
