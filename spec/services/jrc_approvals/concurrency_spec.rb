require 'rails_helper'
require 'timeout'

RSpec.describe 'Approval core independent PostgreSQL connections', type: :model, approval_core: true do
  self.use_transactional_tests = false

  # Rows in these cases are synthetic, committed for independent visibility, and discarded with the entire test database.
  def simultaneous(&block)
    ready, start, results = Queue.new, Queue.new, Queue.new
    threads = 2.times.map do |index|
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do |connection|
          ready << connection.select_value('SELECT pg_backend_pid()')
          start.pop
          begin
            results << [:ok, block.call(index)]
          rescue StandardError => error
            results << [:error, error.class.name, error.message]
          end
        end
      end
    end
    Timeout.timeout(20) do
      pids = 2.times.map { ready.pop }
      expect(pids.uniq.size).to eq(2)
      2.times { start << true }
      threads.each(&:join)
      2.times.map { results.pop }
    end
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end

  it 'replays concurrent identical creation without duplicate request or event' do
    scope = approval_scope
    author, approver = approval_actor(scope), approval_actor(scope)
    approval_publish(scope, author, approval_definition([approver]))
    results = simultaneous { approval_request(scope, author, key: 'concurrent-create').id }
    expect(results.map(&:first)).to eq(%i[ok ok])
    expect(results.map(&:last).uniq.size).to eq(1)
    expect(JrcApprovals::Request.where(account_id: scope[:account].id).count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(account_id: scope[:account].id, event_type: 'request_created').count).to eq(1)
  end

  it 'serializes competing decisions and refuses the stale expected version' do
    scope = approval_scope
    author, a, b = approval_actor(scope), approval_actor(scope), approval_actor(scope)
    approval_publish(scope, author, approval_definition([a, b], mode: 'quorum', quorum: 2))
    request = approval_request(scope, author)
    results = simultaneous do |index|
      approval_vote(scope, [a, b][index], JrcApprovals::Request.find(request.id), expected_version: 0, idempotency_key: "vote-#{index}").id
    end
    expect(results.count { |result| result.first == :ok }).to eq(1)
    expect(results.select { |result| result.first == :error }.first).to eq([:error, 'JrcApprovals::Error', 'VERSION_CONFLICT'])
    expect(request.reload.decisions.count).to eq(1)
    expect(request.lock_version).to eq(1)
    expect(request.state).to eq('pending')
    expect(JrcApprovals::AuditEvent.where(request_id: request.id, event_type: 'decision_recorded').count).to eq(1)
  end
end
