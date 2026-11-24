require 'rails_helper'
require 'timeout'

RSpec.describe 'Ending prospective activation under native account authority' do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable ending readiness database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with native ending execution original evidence'

  def activate_from_connection(account_id, member_id, key, revision)
    target = Account.find(account_id)
    person = target.account_users.find(member_id)
    JrcContactCenter::EndingActions::ActivateRule.new(account: target, member: person, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: key, expected_revision: revision).call
  end

  def waiting_activation(state, key, revision)
    ids = [account.id, member.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:result] << activate_from_connection(*ids, key, revision)
      end
    rescue StandardError => e
      state[:result] << e
    end
  end

  def wait_for_activation_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
  end

  def finish_activation_worker(worker)
    worker&.join(20)
    raise 'Synthetic activation worker remained active' if worker&.alive?
  end

  it 'serializes a repeated activation request on independent connections into one immutable readiness' do
    key = SecureRandom.uuid
    revision = JrcContactCenter::AcwPolicy.new(account: account).revision
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    first = nil
    account.with_lock do
      worker = waiting_activation(state, key, revision)
      wait_for_activation_lock(state)
      first = activate_from_connection(account.id, member.id, key, revision)
    end
    second = Timeout.timeout(20) { state[:result].pop }
    expect(second).to be_a(JrcContactCenter::EndingActionReadiness)
    expect(second.attributes).to eq(first.reload.attributes)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account).count).to eq(1)
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    finish_activation_worker(worker)
  end

  it 'denies activation after a committed current-profile revocation instead of using stale configuration authority' do
    revision = JrcContactCenter::AcwPolicy.new(account: account).revision
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view])
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    account.with_lock do
      worker = waiting_activation(state, SecureRandom.uuid, revision)
      wait_for_activation_lock(state)
      member.update!(custom_role: role)
    end
    expect(Timeout.timeout(20) { state[:result].pop }).to be_a(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::EndingActionReadiness.where(account: account)).to be_empty
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    finish_activation_worker(worker)
  end

  it 'includes an in-flight original call and leg in the activation cutoff even with a future provider start timestamp' do
    revision = JrcContactCenter::AcwPolicy.new(account: account).revision
    state = { ready: Queue.new, result: Queue.new }
    worker = nil
    previous_call = nil
    previous_leg = nil
    account.with_lock do
      worker = waiting_activation(state, SecureRandom.uuid, revision)
      wait_for_activation_lock(state)
      previous_call = new_origin_source_call(started_at: 1.minute.from_now)
      previous_leg = JrcContactCenter::CallLeg.create!(account: account, call_session: previous_call, account_user: member, queue: queue,
                                                       direction: 'inbound', status: 'connected', started_at: previous_call.started_at,
                                                       answered_at: previous_call.answered_at)
    end
    activation = Timeout.timeout(20) { state[:result].pop }
    expect(activation).to be_a(JrcContactCenter::EndingActionReadiness)
    expect(activation.cutoff_call_id).to be >= previous_call.id
    expect(activation.cutoff_leg_id).to be >= previous_leg.id
    expect(previous_call.started_at).to be > activation.created_at
    expect(JrcProjects::Task.where(account: account)).to be_empty
  ensure
    finish_activation_worker(worker)
  end
end
