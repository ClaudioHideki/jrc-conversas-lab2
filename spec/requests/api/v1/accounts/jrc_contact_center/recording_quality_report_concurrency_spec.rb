# frozen_string_literal: true

require 'rails_helper'
require 'timeout'

# Committed synthetic rows and actual independent PostgreSQL backends. The
# external metric read is paused; no source account lock may span that I/O.
RSpec.describe 'Native recording quality report authority contention', :pabx do
  self.use_transactional_tests = false
  include_context 'with native authorized quality review source'

  let(:state) { { ready: Queue.new, results: Queue.new, external: Queue.new, release: Queue.new } }
  let(:metric_reader) { instance_double(JrcVoiceQuality::AnalysisMetricReader) }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable quality report database required' unless owned && !ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    allow(JrcVoiceQuality::AnalysisMetricReader).to receive(:new).and_return(metric_reader)
    allow(metric_reader).to receive(:call) { raise 'Unexpected external read' }
  end

  def worker
    ids = [account.id, member.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        reader = JrcContactCenter::RecordingQualityReport.new(account: Account.find(ids[0]), member: AccountUser.find(ids[1]))
        state[:results] << reader.call({}) { |_source, _relation, metrics| metrics.summary }
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def join_worker(thread)
    thread.join(20)
    raise 'Owned quality report contender remained active' if thread.alive?
  end

  def wait_for_lock(pid)
    query = <<~SQL.squish
      WITH RECURSIVE blockers(pid) AS (
        SELECT unnest(pg_blocking_pids(#{Integer(pid)})) UNION
        SELECT next_blocker.pid FROM blockers
          CROSS JOIN LATERAL unnest(pg_blocking_pids(blockers.pid)) AS next_blocker(pid)
          WHERE blockers.pid <> pg_backend_pid() AND blockers.pid > 0
      ) SELECT EXISTS (SELECT 1 FROM blockers WHERE pid = pg_backend_pid())
    SQL
    Timeout.timeout(8) { sleep 0.02 until ApplicationRecord.connection.select_value(query) == true }
  end

  it 'permits an actual concurrent revocation during external I/O and refuses the completed report after fresh authority' do
    allow(metric_reader).to receive(:call) do
      state[:external] << ApplicationRecord.connection.raw_connection.backend_pid
      Timeout.timeout(8) { state[:release].pop }
      {}
    end
    thread = worker
    begin
      provider_pid = Timeout.timeout(8) { state[:external].pop }
      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute("SET LOCAL lock_timeout = '1500ms'")
        account.lock!
        role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
      end
    ensure
      state[:release] << true
      join_worker(thread)
    end
    expect(provider_pid).not_to eq(ApplicationRecord.connection.raw_connection.backend_pid)
    expect(Timeout.timeout(8) { state[:results].pop }).to be_a(Pundit::NotAuthorizedError)
  end

  it 'proves a waiting PostgreSQL backend and rechecks listening permission before any external metric read' do
    thread = nil
    begin
      account.with_lock do
        thread = worker
        pid = Timeout.timeout(8) { state[:ready].pop }
        wait_for_lock(pid)
        role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view])
      end
    ensure
      join_worker(thread) if thread
    end
    expect(Timeout.timeout(8) { state[:results].pop }).to be_a(Pundit::NotAuthorizedError)
    expect(metric_reader).not_to have_received(:call)
  end
end
