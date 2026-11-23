require 'rails_helper'
require 'timeout'

RSpec.describe 'Ending action scope capture with competing native PostgreSQL connections' do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic scope concurrency database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with a native ending action queue scope'

  def scope_contender(state, queue_id)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        Timeout.timeout(15) { state[:gate].pop }
        state[:results] << connection.select_value("SELECT cc_ending_action_capture_queue_scope(#{Integer(queue_id)})")
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_scope_contenders(state)
    ids = Timeout.timeout(8) { Array.new(2) { state[:ready].pop } }
    raise 'Distinct PostgreSQL connections required' unless ids.uniq.length == 2

    2.times { state[:gate] << true }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{ids.map { |id| Integer(id) }.join(',')}) AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ActiveRecord::Base.connection.uncached { sleep 0.02 until ActiveRecord::Base.connection.select_value(sql).to_i == 2 }
    end
  end

  def competing_scope_captures
    queue_id = queue.id
    state = { ready: Queue.new, gate: Queue.new, results: Queue.new, workers: [] }
    queue.with_lock do
      2.times { state[:workers] << scope_contender(state, queue_id) }
      wait_for_scope_contenders(state)
      yield if block_given?
    end
    results = Timeout.timeout(20) do
      state[:workers].each(&:join)
      Array.new(2) { state[:results].pop }
    end
    raise results.grep(Exception).first if results.any?(Exception)

    results
  ensure
    join_scope_contenders(state) if state
  end

  def join_scope_contenders(state)
    2.times { state[:gate] << true }
    state[:workers].each { |worker| worker.join(20) }
    raise 'Synthetic scope capture still active' if state[:workers].any?(&:alive?)
  end

  it 'serializes duplicate captures without creating a second scope revision' do
    original = scope.attributes.deep_dup
    results = competing_scope_captures
    expect(results).to eq([scope.id, scope.id])
    expect(scopes.count).to eq(1)
    expect(scope.reload.attributes).to eq(original)
  end

  it 'reads the committed remapping after contention instead of reviving the old queue identity' do
    original = scope.attributes.deep_dup
    results = competing_scope_captures { unit.update!(settings: {}) }
    current = scopes.last
    expect(results).to eq([current.id, current.id])
    expect(current.id).not_to eq(original.fetch('id'))
    expect(current.scope_state).to eq('unmapped')
    expect(scopes.pluck(:revision)).to eq([1, 2])
    expect(scope.reload.attributes).to eq(original)
  end

  it 'does not hold a native queue while an upstream issuer update waits for the existing account authority lock' do
    scope
    issuer_id = issuer.id
    state = { ready: Queue.new, gate: Queue.new, results: Queue.new, workers: [] }
    account.with_lock do
      state[:workers] << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          state[:ready] << connection.raw_connection.backend_pid
          Timeout.timeout(15) { state[:gate].pop }
          JrcCustomers::Company.find(issuer_id).update!(active: false)
          state[:results] << :updated
        end
      rescue StandardError => e
        state[:results] << e
      end
      pid = Timeout.timeout(8) { state[:ready].pop }
      state[:gate] << true
      sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
      Timeout.timeout(8) do
        ActiveRecord::Base.connection.uncached { sleep 0.02 until ActiveRecord::Base.connection.select_value(sql).to_i == 1 }
      end
      JrcContactCenter::Queue.transaction(requires_new: true) { queue.lock!('FOR UPDATE NOWAIT') }
    end
    result = Timeout.timeout(20) { state[:results].pop }
    raise result if result.is_a?(Exception)

    expect(result).to eq(:updated)
    expect(scopes.last.scope_state).to eq('invalid')
    expect(scopes.pluck(:revision)).to eq([1, 2])
  ensure
    join_scope_contenders(state) if state
  end
end
