require 'rails_helper'
require 'timeout'

# Actual committed fixtures and independent PostgreSQL connections, never a
# substitute for per-destination receipt/idempotency tests still to be added.
RSpec.describe 'Ending execution lock compatibility with native destinations' do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable ending execution database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with native ending rule configuration'

  def execution_worker(state, &operation)
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:result] << operation.call
      end
    rescue StandardError => e
      state[:result] << e
    end
  end

  def wait_for_execution_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid = #{Integer(pid)} AND wait_event_type = 'Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
  end

  def finish_execution_worker(worker)
    worker&.join(20)
    raise 'Synthetic execution worker remained active' if worker&.alive?
  end

  it 'rejects a nested transaction instead of claiming that an inherited strong account lock was weakened' do
    target = account
    called = false
    expect do
      Account.transaction do
        described = JrcContactCenter::EndingActions::ExecutionTransaction
        described.call(account: target) { called = true }
      end
    end.to raise_error(JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction')
    expect(called).to be(false)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  end

  it 'waits for the existing native authority writer and reads the committed profile without stale privileges' do
    account_id = account.id
    member_id = member.id
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    account.with_lock do
      worker = execution_worker(state) do
        target = Account.find(account_id)
        JrcContactCenter::EndingActions::ExecutionTransaction.call(account: target) do
          person = target.account_users.find(member_id)
          context = { account: target, account_user: person, user: person.user }
          JrcContactCenter::ModulePolicy.new(context, :contact_center).configure?
        end
      end
      wait_for_execution_lock(state)
      member.update!(custom_role: role)
    end
    expect(Timeout.timeout(20) { state[:result].pop }).to be(false)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    finish_execution_worker(worker)
  end

  it 'permits the actual native Projects task insert and its foreign key while the account execution mutex is held' do
    project_id = project.id
    member_id = member.id
    account_id = account.id
    column_id = column.id
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    JrcContactCenter::EndingActions::ExecutionTransaction.call(account: account) do
      worker = execution_worker(state) do
        person = AccountUser.find_by!(id: member_id, account_id: account_id)
        destination = JrcOperations::Access.projects(person).find(project_id)
        JrcProjects::Tasks::Create.call(account_user: person, project: destination,
                                        attributes: { title: 'SYNTHETIC FK-compatible insert', board_column_id: column_id })
      end
      result = Timeout.timeout(8) { state[:result].pop }
      expect(result).to be_a(JrcProjects::Task)
      expect(result.account_id).to eq(account_id)
    end
    expect(JrcProjects::Task.where(account: account).count).to eq(1)
  ensure
    finish_execution_worker(worker)
  end

  it 'allows an existing project writer to finish while the executor waits for its actual project lock' do
    destination = project
    person = member
    column_id = column.id
    account_id = account.id
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    destination.with_lock do
      worker = execution_worker(state) do
        target = Account.find(account_id)
        JrcContactCenter::EndingActions::ExecutionTransaction.call(account: target) do
          acting = target.account_users.find(person.id)
          native = JrcOperations::Access.projects(acting).find(destination.id)
          JrcProjects::Tasks::Create.call(account_user: acting, project: native,
                                          attributes: { title: 'SYNTHETIC queued executor', board_column_id: column_id })
        end
      end
      wait_for_execution_lock(state)
      first = JrcProjects::Tasks::Create.call(account_user: person, project: destination,
                                             attributes: { title: 'SYNTHETIC earlier native writer', board_column_id: column_id })
      expect(first).to be_persisted
    end
    expect(Timeout.timeout(20) { state[:result].pop }).to be_a(JrcProjects::Task)
    expect(JrcProjects::Task.where(account: account).count).to eq(2)
  ensure
    finish_execution_worker(worker)
  end
end
