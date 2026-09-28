# frozen_string_literal: true
require 'rails_helper'
require 'timeout'

# Explicit opt-in: run only on a dedicated disposable test database. Test data is
# committed so separate PostgreSQL connections can contend on the actual unit lock.
# No account-wide cleanup or deletion of pre-existing records is performed here.
RSpec.describe 'JRC Service Desk CP4 real concurrent creation', :sd_concurrency, type: :service do
  self.use_transactional_tests = false
  include_context 'JRC Service Desk domain'
  around do |example|
    if ENV['JRC_SD_CONCURRENCY'] == '1' && Rails.env.test?
      example.run
    else
      skip 'PENDENTE - opt-in JRC_SD_CONCURRENCY=1 on a disposable Docker/local test database'
    end
  end

  def simultaneous_creates(attributes)
    unit_id = sd_unit.id
    actor_context = sd_context
    sd_status
    sd_priority
    sd_contact
    raise 'Concurrent fixture data must be committed' if ActiveRecord::Base.connection.transaction_open?
    gate = Queue.new
    outcomes = Queue.new
    threads = attributes.map do |values|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          begin
            ticket = JrcServiceDesk::CreateTicketWorkflowService.new(user_context: actor_context).call(
              unit_id: unit_id, attributes: values, idempotency_key: 'concurrent-same-key')
            outcomes << ticket.id
          rescue StandardError => error
            outcomes << error
          end
        end
      end
    end
    attributes.length.times { gate << true }
    Timeout.timeout(30) { threads.each(&:join) }
    attributes.length.times.map { outcomes.pop }
  ensure
    # Cancels only the test workers after timeout; never background work.
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end

  it 'serializes identical simultaneous requests into exactly one ticket and one marker' do
    values = sd_create_attributes
    outcomes = simultaneous_creates([values, values])
    expect(outcomes.all? { |value| value.is_a?(Integer) }).to be(true)
    expect(outcomes.uniq.length).to eq(1)
    tickets = JrcServiceDesk::Ticket.where(account_id: sd_account.id, unit_id: sd_unit.id)
    expect(tickets.count).to eq(1)
    expect(tickets.first.ticket_events.where(event_type: 'creation_context_recorded').count).to eq(1)
  end

  it 'rejects one conflicting simultaneous intent rather than applying both' do
    values = sd_create_attributes
    outcomes = simultaneous_creates([values, values.merge(title: 'Conflicting concurrent intent')])
    expect(outcomes.count { |value| value.is_a?(Integer) }).to eq(1)
    expect(outcomes.count { |value| value.is_a?(JrcServiceDesk::IdempotencyConflict) }).to eq(1)
    expect(JrcServiceDesk::Ticket.where(account_id: sd_account.id, unit_id: sd_unit.id).count).to eq(1)
  end
end
