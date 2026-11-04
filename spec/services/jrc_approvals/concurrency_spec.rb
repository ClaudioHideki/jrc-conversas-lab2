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

  it 'serializes reciprocal delegation grants so only one overlapping direction is committed' do
    scope = approval_scope
    author = approval_actor(scope)
    a = approval_actor(scope)
    b = approval_actor(scope)
    policy = approval_publish(scope, author, approval_definition([a, b]).merge('delegation_allowed' => true))
    starts_at = Time.current
    ends_at = 1.hour.from_now
    results = simultaneous do |index|
      principal, delegate = index.zero? ? [a, b] : [b, a]
      JrcApprovals::Delegations.new(account: scope[:account], user: author.user).create!(
        policy_version_id: policy.current_version_id, step_code: 'review', principal_id: principal.id, delegate_id: delegate.id,
        actions: ['approved'], reason: 'Synthetic concurrent coverage', starts_at: starts_at, ends_at: ends_at
      ).id
    end
    expect(results.count { |result| result.first == :ok }).to eq(1)
    expect(results.find { |result| result.first == :error }).to eq([:error, 'JrcApprovals::Error', 'INVALID_DELEGATION'])
    expect(JrcApprovals::Delegation.where(account_id: scope[:account].id).count).to eq(1)
    expect(JrcApprovals::AuditEvent.where(account_id: scope[:account].id, event_type: 'delegation_granted').count).to eq(1)
  end

  it 'replays simultaneous own grants with one immutable audit entry' do
    scope = approval_scope
    principal, recipient = approval_actor(scope), approval_actor(scope)
    starts_at, ends_at = 1.minute.ago, 1.hour.from_now
    results = simultaneous do
      JrcApprovals::OwnDelegations.new(account: scope[:account], user: principal.user).create!(delegate_id: recipient.id,
        issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, actions: ['approved'],
        reason: 'Synthetic simultaneous own grant', starts_at: starts_at, ends_at: ends_at, idempotency_key: 'own-concurrent').id
    end
    expect(results.map(&:first)).to eq(%i[ok ok]), results.inspect
    expect(results.map(&:last).uniq.size).to eq(1)
    expect(JrcApprovals::OwnDelegations.grants(scope[:account]).size).to eq(1)
  end

  it 'serializes a scoped grant against an opposing global grant to prevent a mixed cycle' do
    scope = approval_scope
    author, a, b = approval_actor(scope), approval_actor(scope), approval_actor(scope)
    rule = approval_publish(scope, author, approval_definition([b]).merge('delegation_allowed' => true))
    starts_at, ends_at = 1.minute.ago, 1.hour.from_now
    results = simultaneous do |index|
      if index.zero?
        JrcApprovals::OwnDelegations.new(account: scope[:account], user: a.user).create!(delegate_id: b.id,
          issuer_company_id: scope[:company].id, business_unit_id: scope[:unit].id, actions: ['approved'],
          reason: 'Synthetic mixed concurrent global grant', starts_at: starts_at, ends_at: ends_at, idempotency_key: 'own-mixed').id
      else
        JrcApprovals::Delegations.new(account: scope[:account], user: author.user).create!(policy_version_id: rule.current_version_id,
          step_code: 'review', principal_id: b.id, delegate_id: a.id, actions: ['approved'],
          reason: 'Synthetic mixed concurrent scoped grant', starts_at: starts_at, ends_at: ends_at).id
      end
    end
    expect(results.count { |row| row.first == :ok }).to eq(1), results.inspect
    expect(results.find { |row| row.first == :error }).to eq([:error, 'JrcApprovals::Error', 'INVALID_DELEGATION'])
  end
end
