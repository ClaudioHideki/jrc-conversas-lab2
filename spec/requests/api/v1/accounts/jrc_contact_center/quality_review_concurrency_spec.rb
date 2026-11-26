# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

# Real committed PostgreSQL contenders; no mocked lock, writer, policy, persistence or audit.
RSpec.describe 'Native human quality review contention', :pabx do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable quality review database required' unless owned
    raise 'Committed quality review fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native authorized quality review source'

  let(:snapshot) { JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: record.external_unique_id) }
  let(:values) do
    { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC simultaneous correction', 'adjusted_themes' => [],
      'recommendation_ids' => [], 'justification' => 'SYNTHETIC reviewed', 'expected_revision' => 0,
      'expected_source_sha256' => snapshot.sha256, 'request_id' => SecureRandom.uuid }
  end
  let(:state) { { ready: Queue.new, results: Queue.new } }

  def quality_worker(input)
    account_id = account.id
    member_id = member.id
    recording_id = record.id
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        writer = JrcContactCenter::QualityReviewWrite.new(account: Account.find(account_id), member: AccountUser.find(member_id))
        state[:results] << writer.call(recording_id, input)
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_quality_lock
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

  def join_quality_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Owned quality review contender remained active' if worker.alive?
    end
  end

  it 'proves two actual waiting backends and commits exactly one revision when users submit the same old counter' do
    first = values
    second = values.merge('request_id' => SecureRandom.uuid, 'classification' => 'neutral')
    workers = []
    pids = []
    begin
      account.with_lock do
        workers << quality_worker(first)
        pids << wait_for_quality_lock
        workers << quality_worker(second)
        pids << wait_for_quality_lock
      end
    ensure
      join_quality_workers(workers)
    end
    results = Array.new(2) { Timeout.timeout(8) { state[:results].pop } }
    expect(pids.uniq.length).to eq(2)
    expect(results.count { |row| row.is_a?(JrcContactCenter::QualityReviewRevision) }).to eq(1)
    expect(results.select { |row| row.is_a?(JrcContactCenter::OperationError) }.map(&:message)).to eq(['quality_review_revision_changed'])
    expect(JrcContactCenter::QualityReviewRevision.where(account: account).pluck(:revision)).to eq([1])
  end

  it 'acknowledges simultaneous redelivery with one immutable revision and one native audit' do
    input = values
    workers = []
    begin
      account.with_lock do
        2.times do
          workers << quality_worker(input)
          wait_for_quality_lock
        end
      end
    ensure
      join_quality_workers(workers)
    end
    results = Array.new(2) { Timeout.timeout(8) { state[:results].pop } }
    expect(results).to all(be_a(JrcContactCenter::QualityReviewRevision))
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(Audited.audit_class.where(auditable: results.first, action: 'create').count).to eq(1)
  end

  it 'rechecks the explicit current permission after waiting and creates no human revision for a revoked agent' do
    input = values
    workers = []
    begin
      account.with_lock do
        workers << quality_worker(input)
        wait_for_quality_lock
        role.update!(permissions: recording_rights)
      end
    ensure
      join_quality_workers(workers)
    end
    expect(Timeout.timeout(8) { state[:results].pop }).to be_a(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::QualityReviewRevision.where(account: account)).to be_empty
  end
end
