# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

# Real committed contenders and PostgreSQL lock graph. No persistence, permission
# or Projects execution service is replaced.
RSpec.describe 'Native recording task idempotence and current authority contention', :pabx do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = [Rails.env.test?, ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted',
             config.configuration_hash[:host] == '127.0.0.1', ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15',
             ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'].all?
    raise 'Owned disposable recording task database required' unless owned
    raise 'Committed recording task fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native manual recording task destination'

  let(:state) { { ready: Queue.new, results: Queue.new } }

  def task_worker(values)
    ids = [account.id, member.id, record.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        writer = JrcContactCenter::RecordingTaskWrite.new(account: Account.find(ids[0]), member: AccountUser.find(ids[1]))
        state[:results] << writer.call(ids[2], values)
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_recording_task_lock
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

  def join_task_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Owned recording task contender remained active' if worker.alive?
    end
  end

  it 'proves two actual waiting backends and commits one native Task, audit and receipt for simultaneous identical requests' do
    values = input
    workers = []
    pids = []
    begin
      account.with_lock do
        2.times do
          workers << task_worker(values.deep_dup)
          pids << wait_for_recording_task_lock
        end
      end
    ensure
      join_task_workers(workers)
    end
    results = Array.new(2) { Timeout.timeout(8) { state[:results].pop } }
    expect(pids.uniq.length).to eq(2)
    expect(results).to all(be_a(JrcContactCenter::RecordingTaskLink))
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
    expect(JrcContactCenter::RecordingTaskLink.where(account: account).count).to eq(1)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count).to eq(1)
  end

  it 'rechecks current Project create authority after waiting and creates no task when that permission was revoked' do
    values = input
    workers = []
    begin
      account.with_lock do
        workers << task_worker(values)
        wait_for_recording_task_lock
        member.update!(jrc_projects_permissions: { 'projects.task.create' => false, 'projects.task.assign' => true })
      end
    ensure
      join_task_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::RecordingTaskLink.where(account: account)).to be_empty
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created')).to be_empty
  end
end
