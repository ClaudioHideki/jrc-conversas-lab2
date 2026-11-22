require 'rails_helper'
require 'timeout'

RSpec.describe 'All-scope pause actual HTTP concurrency', :approval_core, type: :request do
  self.use_transactional_tests = false

  # This must run before any shared fixture writes. Database names alone do not establish ownership.
  before do
    config = ApplicationRecord.connection_db_config
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == 'corporate_gratuity_disposable'
    raise 'Exclusive hosted synthetic pause concurrency database required' unless owned
    raise 'Committed pause fixtures required' if ApplicationRecord.connection.transaction_open?
  end

  include_context 'with all-scope native pause approval'

  let(:parallel) { { workers: [], ready: Queue.new, gate: Queue.new, results: Queue.new } }

  before do
    publish_all_pause_policies
    parallel[:headers] = actor.create_new_auth_token
  end

  after do
    parallel[:workers].length.times { parallel[:gate] << true }
    parallel[:workers].each { |worker| worker.join(20) }
    raise 'Owned pause worker still active' if parallel[:workers].any?(&:alive?)

    # Keep immutable synthetic receipts until the already-owned runner discards its own database/container.
    # Do not disable triggers, delete history or introduce a production-capable cleanup path.
  end

  def dispatch_pause_approval(action, body)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/deferred_pause_request#{action}"
    parallel[:workers] << Thread.new do
      ApplicationRecord.connection_pool.with_connection do
        parallel[:ready] << ApplicationRecord.connection.raw_connection.backend_pid
        Timeout.timeout(15) { parallel[:gate].pop }
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post(endpoint, headers: parallel[:headers], params: body, as: :json)
        parallel[:results] << { status: session.response.status, body: session.response.parsed_body }
      end
    rescue StandardError => e
      parallel[:results] << e
    end
  end

  def wait_for_pause_locks(count)
    pids = Timeout.timeout(8) { Array.new(count) { parallel[:ready].pop } }
    count.times { parallel[:gate] << true }
    quoted = pids.map { |pid| ApplicationRecord.connection.quote(pid) }.join(',')
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{quoted}) AND wait_event_type = 'Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == count }
    end
  end

  def pause_results(count)
    rows = Timeout.timeout(25) do
      parallel[:workers].each(&:join)
      Array.new(count) { parallel[:results].pop }
    end
    error = rows.grep(Exception).first
    raise error if error

    rows
  end

  def reviewed_body(input)
    preview = JrcContactCenter::PauseApprovalIntent.new(context: pause_context).call(input)
    { deferred_pause_request: input, expected_approval_digest: preview.fetch('digest') }
  end

  it 'commits one canonical intent and a complete two-company request set for distinct concurrent UUIDs' do
    first = reviewed_body(values)
    second = reviewed_body(values.merge(command_id: SecureRandom.uuid))
    account.with_lock do
      [first, second].each { |body| dispatch_pause_approval('', body) }
      wait_for_pause_locks(2)
    end
    expect(pause_results(2).pluck(:status).sort).to eq([200, 409])
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account).count).to eq(1)
    expect(JrcContactCenter::PauseApprovalReview.where(account: account).count).to eq(1)
    expect(JrcContactCenter::PauseApprovalScope.where(account: account).count).to eq(2)
    expect(pause_requests.size).to eq(2)
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end

  it 'recovers one exact durable intent and Central request set from duplicate concurrent confirmations' do
    body = reviewed_body(values)
    account.with_lock do
      2.times { dispatch_pause_approval('', body) }
      wait_for_pause_locks(2)
    end
    rows = pause_results(2)
    expect(rows.pluck(:status)).to eq([200, 200])
    expect(rows.map { |row| row.fetch(:body).dig('receipt', 'request_id') }).to eq([values.fetch(:command_id)] * 2)
    expect(JrcContactCenter::PauseApprovalReview.where(account: account).count).to eq(1)
    expect(JrcContactCenter::PauseApprovalScope.where(account: account).count).to eq(2)
    expect(pause_requests.size).to eq(2)
  end

  it 'rechecks operating permissions after waiting rather than recording any partial approval request' do
    body = reviewed_body(values)
    account.with_lock do
      dispatch_pause_approval('', body)
      wait_for_pause_locks(1)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_approvals_request_create])
    end
    expect(pause_results(1).first.fetch(:status)).to eq(401)
    expect(JrcContactCenter::DeferredPauseRequest.where(account: account)).to be_empty
    expect(JrcContactCenter::PauseApprovalReview.where(account: account)).to be_empty
    expect(pause_requests).to be_empty
  end

  it 'applies one real native paused event for simultaneous confirmed consumption after both Central decisions' do
    row = create_reviewed_pause
    approve_pause_requests
    body = { deferred_pause_request: { request_id: row.request_id, expected_state_version: values.fetch(:expected_state_version) } }
    account.with_lock do
      2.times { dispatch_pause_approval('/apply', body) }
      wait_for_pause_locks(2)
    end
    rows = pause_results(2)
    expect(rows.pluck(:status)).to eq([200, 200])
    expect(rows.map { |item| item.fetch(:body).dig('receipt', 'state') }).to eq(%w[applied applied])
    expect(row.reload.state).to eq('applied')
    events = JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')
    expect(events.count).to eq(1)
    expect(events.sole.metadata.fetch('provider_confirmed')).to be(false)
    expect(pause_requests.size).to eq(2)
  end

  it 'does not consume an approved source after current authority is revoked while the apply operation waits' do
    row = create_reviewed_pause
    approve_pause_requests
    body = { deferred_pause_request: { request_id: row.request_id, expected_state_version: values.fetch(:expected_state_version) } }
    account.with_lock do
      dispatch_pause_approval('/apply', body)
      wait_for_pause_locks(1)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_approvals_request_create])
    end
    expect(pause_results(1).first.fetch(:status)).to eq(401)
    expect(row.reload.state).to eq('pending')
    expect(pause_requests.map(&:state)).to eq(%w[approved approved])
    expect(JrcContactCenter::AgentStateEvent.where(account: account, state: 'paused')).to be_empty
  end
end
