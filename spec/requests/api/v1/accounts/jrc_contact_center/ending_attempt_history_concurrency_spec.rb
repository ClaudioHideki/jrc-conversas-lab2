require 'rails_helper'
require 'timeout'

RSpec.describe 'Native ending history authority after real lock contention' do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable ending history concurrency database required' unless owned
    raise 'Committed ending history concurrency fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  before do
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: SecureRandom.uuid,
                                                      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def history_worker(operator, qualification_id, state)
    ids = [account.id, operator.id, qualification_id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:result] << JrcContactCenter::EndingActions::AttemptHistory.new(
          account: Account.find(ids[0]), member: AccountUser.find(ids[1]), qualification_id: ids[2]
        ).call
      end
    rescue StandardError => e
      state[:result] << e
    end
  end

  def wait_for_history_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
  end

  it 'rejects an operate permission revoked while the history reader actually waits on the native account mutex' do
    id = qualification.id
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    account.with_lock do
      worker = history_worker(member, id, state)
      wait_for_history_lock(state)
      member.update!(custom_role: role)
    end
    result = Timeout.timeout(20) { state[:result].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    worker&.join(20)
    raise 'Synthetic history worker remained active' if worker&.alive?
  end

  it 'hides a private destination removed while the history reader waits without erasing its actual success' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    row = JrcContactCenter::EndingActions::QueueProjectAttempt.new(account: account, origin_id: original.id,
                                                                   rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid).call
    JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: row.id).call
    project = JrcProjects::Project.where(account: account).sole
    project.update!(visibility: 'private')
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    account.with_lock do
      worker = history_worker(operator, original.source_qualification_id, state)
      wait_for_history_lock(state)
      project.project_members.where(account: account, user_id: operator.user_id).sole.destroy!
    end
    result = Timeout.timeout(20) { state[:result].pop }
    expect(result.fetch(:items).sole).to include(outcome: 'succeeded', target: nil)
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole.outcome).to eq('succeeded')
  ensure
    worker&.join(20)
    raise 'Synthetic history worker remained active' if worker&.alive?
  end
end
