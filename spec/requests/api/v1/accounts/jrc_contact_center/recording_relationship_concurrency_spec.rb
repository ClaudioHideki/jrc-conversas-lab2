# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

# Real commits, independent PostgreSQL backends and native portfolio row locks.
RSpec.describe 'Native recording Relationship transaction contention', :pabx do
  self.use_transactional_tests = false
  include_context 'with native recording Relationship intake'

  let(:state) { { ready: Queue.new, results: Queue.new } }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable recording Relationship database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  def relationship_writer
    JrcContactCenter::RecordingRelationshipWrite.new(account: account, member: member)
  end

  def relationship_worker(values)
    ids = [account.id, member.id, record.id]
    ready, results = state.values_at(:ready, :results)
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        ready << connection.raw_connection.backend_pid
        writer = JrcContactCenter::RecordingRelationshipWrite.new(account: Account.find(ids[0]), member: AccountUser.find(ids[1]))
        results << writer.call(ids[2], values)
      end
    rescue StandardError => e
      results << e
    end
  end

  def wait_for_relationship_lock
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

  def join_relationship_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Owned recording Relationship contender remained active' if worker.alive?
    end
  end

  it 'proves two waiting backends and commits one native activity and action for simultaneous identical requests' do
    input = relationship_input.deep_dup
    workers = []
    pids = []
    begin
      assignment.with_lock do
        2.times do
          workers << relationship_worker(input.deep_dup)
          pids << wait_for_relationship_lock
        end
      end
    ensure
      join_relationship_workers(workers)
    end
    results = Array.new(2) { Timeout.timeout(8) { state[:results].pop } }
    expect(pids.uniq.length).to eq(2)
    expect(results).to all(be_a(Hash))
    expect(results.map { |row| row.fetch(:activity_id) }.uniq.length).to eq(1)
    expect(results.map { |row| row.fetch(:replayed) }).to contain_exactly(false, true)
    expect(JrcCrm::Activity.where(account: account).count).to eq(1)
    expect(assignment.actions.count).to eq(1)
  end

  it 'rechecks current Relationship work authority after an actual native portfolio lock wait' do
    input = relationship_input.deep_dup
    workers = []
    begin
      assignment.with_lock do
        workers << relationship_worker(input)
        wait_for_relationship_lock
        role.update!(permissions: role.permissions - ['jrc_relationship_manage'])
      end
    ensure
      join_relationship_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(JrcCrm::Activity.where(account: account)).to be_empty
    expect(assignment.actions).to be_empty
  end

  it 'rolls back real activity, action and audits after origin persistence fails and accepts one explicit identical retry' do
    input = relationship_input.deep_dup
    connection = ApplicationRecord.connection
    constraint = "cc_synthetic_relationship_origin_#{Integer(account.id)}"
    before_audits = JrcCrm::AuditEvent.where(account: account).pluck(:id)
    begin
      condition = "account_id <> #{Integer(account.id)} OR NOT (metadata ? 'control_desk_recording_origin')"
      connection.add_check_constraint(JrcRelationship::Action.table_name, condition, name: constraint)
      installed = true
      expect { relationship_writer.call(record.id, input) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(JrcCrm::Activity.where(account: account)).to be_empty
      expect(assignment.actions).to be_empty
      expect(JrcCrm::AuditEvent.where(account: account).pluck(:id)).to eq(before_audits)
    ensure
      connection.remove_check_constraint(JrcRelationship::Action.table_name, name: constraint) if installed
    end
    first = relationship_writer.call(record.id, input)
    expect(relationship_writer.call(record.id, input)).to include(activity_id: first.fetch(:activity_id), replayed: true)
    expect(JrcCrm::Activity.where(account: account).pluck(:id)).to eq([first.fetch(:activity_id).to_i])
    expect(assignment.actions.count).to eq(1)
  end
end
