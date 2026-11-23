require 'rails_helper'
require 'timeout'

# Prepared, unapplied and unexecuted. No provider is invoked and no destination task is created.
RSpec.describe 'Ending rule versions with competing native PostgreSQL connections' do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic ending rule concurrency database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with native ending rule configuration'

  def ending_rule_contender(state, input, revision)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        target = Account.find(account.id)
        person = target.account_users.find(member.id)
        state[:results] << JrcContactCenter::EndingActions::ConfigureRule.new(
          account: target, member: person, input: input.deep_dup, expected_revision: revision
        ).call
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_ending_rule_contenders(state, count: 2)
    ids = Timeout.timeout(8) { Array.new(count) { state[:ready].pop } }
    raise 'Independent PostgreSQL connections required' unless ids.uniq.length == count

    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{ids.map { |id| Integer(id) }.join(',')}) AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == count }
    end
  end

  def competing_ending_rules
    input = rule_input.deep_dup
    revision = policy.revision
    state = { ready: Queue.new, results: Queue.new, workers: [] }
    account.with_lock do
      2.times { state[:workers] << ending_rule_contender(state, input, revision) }
      wait_for_ending_rule_contenders(state)
      yield if block_given?
    end
    Timeout.timeout(20) do
      state[:workers].each(&:join)
      Array.new(2) { state[:results].pop }
    end
  ensure
    verify_ending_rule_workers_finished(state) if state
  end

  def verify_ending_rule_workers_finished(state)
    state[:workers].each { |worker| worker.join(20) }
    raise 'Synthetic ending rule writer still active' if state[:workers].any?(&:alive?)
  end

  def pending_ending_history_reader(state, version)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        target = Account.find(account.id)
        state[:ready] << connection.raw_connection.backend_pid
        JrcContactCenter::AuthorityTransaction.call(account: target, member: nil) do
          state[:results] << JrcContactCenter::EndingActions::BlockingRevision.new(
            account: target, version_id: version.id, rule_code: 'SYNTHETIC_RULE'
          ).call
        end
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  it 'serializes actual overlapping stale writes into one immutable version and one conflict without a task' do
    results = competing_ending_rules
    expect(results.count { |result| result.is_a?(Hash) }).to eq(1)
    errors = results.grep(JrcContactCenter::OperationError)
    expect(errors.map(&:code)).to eq(['stale_configuration_revision'])
    expect(JrcContactCenter::EndingActionVersion.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect { JrcContactCenter::EndingActions::Catalogue.new(account: account.reload).verify_synchronized! }.not_to raise_error
  end

  it 'rechecks committed profile revocation after waiting instead of using the callers earlier configure authority' do
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    results = competing_ending_rules { member.update!(custom_role: role) }
    expect(results.all?(Pundit::NotAuthorizedError)).to be(true)
    expect(JrcContactCenter::EndingActionVersion.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(account.reload.settings.fetch(JrcContactCenter::AcwPolicy::KEY)).not_to have_key('voice_ending_automations')
  end

  it 'observes a committed deactivation after the original pending reader actually waits on the native account transaction' do
    configure_native_ending_rule
    version = JrcContactCenter::EndingActionVersion.where(account: account).sole
    state = { ready: Queue.new, results: Queue.new, workers: [] }
    account.with_lock do
      state[:workers] << pending_ending_history_reader(state, version)
      wait_for_ending_rule_contenders(state, count: 1)
      configure_native_ending_rule(rule_input.merge('active' => false))
    end
    expect(Timeout.timeout(20) { state[:results].pop }).to eq(2)
    expect(version.reload.definition.fetch('entries').first.fetch('active')).to be(true)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    verify_ending_rule_workers_finished(state) if state
  end
end
