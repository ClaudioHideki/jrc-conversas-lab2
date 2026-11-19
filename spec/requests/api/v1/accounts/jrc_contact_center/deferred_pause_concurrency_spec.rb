require 'rails_helper'
require 'timeout'

RSpec.describe 'Deferred pause real HTTP concurrency', type: :request do
  self.use_transactional_tests = false

  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:payload) do
    { command_id: SecureRandom.uuid, reason_code: 'lunch',
      expected_state_version: JrcContactCenter::AgentStateSnapshot.new(account_user: member).version,
      expected_request_revision: JrcContactCenter::DeferredPauseRevision.token(account: account, member: member) }
  end
  let(:workers) { [] }
  let(:ready) { Queue.new }
  let(:gate) { Queue.new }
  let(:results) { Queue.new }
  let(:state) { {} }

  before do
    owned = Rails.env.test? && ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic concurrency database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?

    state[:ready] = true
    account.enable_features!('jrc_contact_center')
    headers
  end

  include_context 'with a native pending voice ACW for deferred pause'

  after do
    if state[:ready]
      workers.length.times { gate << true }
      workers.each { |worker| worker.join(20) }
      raise 'Synthetic deferred pause request still active' if workers.any?(&:alive?)

      JrcContactCenter::Qualification.where(account: account).destroy_all
      JrcContactCenter::CallLeg.where(account: account).destroy_all
      JrcContactCenter::CallSession.where(account: account).destroy_all
      JrcContactCenter::AgentStateEvent.where(account: account).destroy_all
      account.destroy!
    end
  end

  # Real authenticated HTTP requests wait on the same PostgreSQL Account mutex.
  def dispatch_pause(method, values)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/deferred_pause_request"
    workers << Thread.new { perform_pause_request(method, endpoint, values) }
  end

  def perform_pause_request(method, endpoint, values)
    ActiveRecord::Base.connection_pool.with_connection do
      ready << ActiveRecord::Base.connection.raw_connection.backend_pid
      Timeout.timeout(15) { gate.pop }
      session = ActionDispatch::Integration::Session.new(Rails.application)
      params = method == :post ? { deferred_pause_request: values } : values
      session.public_send(method, endpoint, headers: headers, params: params, as: :json)
      results << { status: session.response.status, body: session.response.parsed_body }
    end
  rescue StandardError => e
    results << e
  end

  def wait_for_real_locks(count)
    ids = Timeout.timeout(8) { Array.new(count) { ready.pop } }
    count.times { gate << true }
    connection = ActiveRecord::Base.connection
    quoted = ids.map { |id| connection.quote(id) }.join(',')
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{quoted}) AND wait_event_type = 'Lock'"
    Timeout.timeout(8) { connection.uncached { sleep 0.02 until connection.select_value(sql).to_i == count } }
  end

  def collected_results(count)
    rows = Timeout.timeout(20) do
      workers.each(&:join)
      Array.new(count) { results.pop }
    end
    errors = rows.grep(Exception)
    raise errors.first if errors.any?

    rows
  end

  it 'persists one pending request when concurrent operations have different UUIDs' do
    account.with_lock do
      2.times { dispatch_pause(:post, payload.merge(command_id: SecureRandom.uuid)) }
      wait_for_real_locks(2)
    end
    rows = collected_results(2)
    expect(rows.pluck(:status).sort).to eq([200, 409])
    expect(JrcContactCenter::DeferredPauseRequest.active.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end

  it 'recovers the same durable receipt for simultaneous copies of one exact request' do
    account.with_lock do
      2.times { dispatch_pause(:post, payload) }
      wait_for_real_locks(2)
    end
    rows = collected_results(2)
    expect(rows.pluck(:status)).to eq([200, 200])
    expect(rows.map { |row| row.fetch(:body).dig('item', 'deferred_pause_request', 'request_id') }).to eq([payload[:command_id]] * 2)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account).count).to eq(1)
    expect(Audited::Audit.where(associated: account, comment: JrcContactCenter::DeferredPauseAudit::COMMENT).count).to eq(1)
  end

  it 'rechecks operating authority after waiting rather than committing a revoked request' do
    account.with_lock do
      JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
      dispatch_pause(:post, payload)
      wait_for_real_locks(1)
    end
    row = collected_results(1).first
    expect(row.fetch(:status)).to eq(401)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(Audited::Audit.where(associated: account, comment: JrcContactCenter::DeferredPauseAudit::COMMENT)).to be_empty
  end

  it 'does not turn a late cancellation into an unpause after the native transition won the account lock' do
    manager = JrcContactCenter::DeferredPauseManager.new(account: account, member: member)
    record = manager.request!(payload)
    account.with_lock do
      dispatch_pause(:delete, { request_id: record.request_id })
      wait_for_real_locks(1)
      JrcContactCenter::QualificationManager.new(account: account, member: member).complete!(
        pending_pause_qualification, { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC completion before late cancellation' }
      )
    end
    row = collected_results(1).first
    expect(row.fetch(:status)).to eq(409)
    expect(row.fetch(:body).fetch('error')).to eq('pause_already_applied')
    expect(record.reload.state).to eq('applied')
    expect(member.reload.availability).to eq('lunch_break')
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused').count).to eq(1)
  end

  it 'rejects a delayed creation after another request and withdrawal have won the account lock' do
    manager = JrcContactCenter::DeferredPauseManager.new(account: account, member: member)
    stale = payload.dup
    account.with_lock do
      dispatch_pause(:post, stale)
      wait_for_real_locks(1)
      winner = manager.request!(payload.merge(command_id: SecureRandom.uuid))
      manager.cancel!(winner.request_id)
    end
    row = collected_results(1).first
    expect(row.fetch(:status)).to eq(409)
    expect(row.fetch(:body).fetch('error')).to eq('stale_pause_request')
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account).pluck(:state)).to eq(['cancelled'])
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end
end
