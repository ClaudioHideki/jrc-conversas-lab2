require 'rails_helper'
require 'timeout'

RSpec.describe 'Private operational ACW responses with real HTTP contenders', type: :request do
  self.use_transactional_tests = false

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' &&
            ActiveRecord::Base.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned synthetic form concurrency database required' unless owned
    raise 'Committed fixtures required' if ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with an owned immutable operational ACW form'

  # Each contender authenticates normally, uses a different PG connection and waits on the real native Account lock.
  def draft_contender(state, token, values)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}/draft"
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        state[:ready] << ActiveRecord::Base.connection.raw_connection.backend_pid
        Timeout.timeout(15) { state[:gate].pop }
        state[:results] << perform_private_draft(endpoint, token, values)
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def perform_private_draft(endpoint, token, values)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.patch(endpoint, headers: token, params: values, as: :json)
    { status: session.response.status, body: session.response.parsed_body }
  end

  def wait_for_form_contenders(state, count)
    ids = Timeout.timeout(8) { Array.new(count) { state[:ready].pop } }
    raise 'Distinct PostgreSQL connections required' unless ids.uniq.length == count

    count.times { state[:gate] << true }
    quoted = ids.map { |id| ActiveRecord::Base.connection.quote(id) }.join(',')
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid IN (#{quoted}) AND wait_event_type = 'Lock'"
    Timeout.timeout(8) do
      ActiveRecord::Base.connection.uncached do
        sleep 0.02 until ActiveRecord::Base.connection.select_value(sql).to_i == count
      end
    end
  end

  def competing_drafts(values)
    token = actor.create_new_auth_token
    state = { ready: Queue.new, gate: Queue.new, results: Queue.new, workers: [] }
    account.with_lock do
      values.each { |value| state[:workers] << draft_contender(state, token, value) }
      wait_for_form_contenders(state, values.length)
      yield if block_given?
    end
    collect_form_results(state, values.length)
  ensure
    join_form_contenders(state) if state
  end

  def collect_form_results(state, count)
    rows = Timeout.timeout(20) do
      state[:workers].each(&:join)
      Array.new(count) { state[:results].pop }
    end
    raise rows.grep(Exception).first if rows.any?(Exception)

    rows
  end

  def join_form_contenders(state)
    state.fetch(:workers).length.times { state[:gate] << true }
    state.fetch(:workers).each { |worker| worker.join(20) }
    raise 'Synthetic qualification request still active' if state.fetch(:workers).any?(&:alive?)
  end

  it 'accepts exactly one private draft when different actual HTTP requests expect the same manual revision' do
    previous = JrcContactCenter::QualificationDraftRevision.token(record)
    values = %w[A B].map do |suffix|
      { expected_draft_revision: previous,
        qualification: { reason_code: 'order', acw_form_answers: { rule[:id] => { 'feedback' => "SYNTHETIC contender #{suffix}" } } } }
    end
    rows = competing_drafts(values)
    expect(rows.pluck(:status).sort).to eq([200, 409])
    winner = rows.find { |row| row[:status] == 200 }.fetch(:body).fetch('item')
    expect(service.state.answers).to eq(winner.fetch('acw_form_context').fetch('answers'))
    expect(JrcContactCenter::QualificationDraftRevision.token(record.reload)).to eq(winner.fetch('draft_revision'))
    expect(record.completed_at).to be_nil
    expect(Audited.audit_class.where(auditable: record).pluck(:audited_changes).to_json).not_to include('SYNTHETIC contender')
  end

  it 'rejects a queued private draft after eligibility is revoked while preserving all persisted answers' do
    previous = JrcContactCenter::QualificationDraftRevision.token(record)
    values = { expected_draft_revision: previous, qualification: { reason_code: 'order', acw_form_answers: answers } }
    rows = competing_drafts([values]) { JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false) }
    expect(rows.first.fetch(:status)).to eq(401)
    expect(service.state.answers).to eq({})
    expect(record.reload.completed_at).to be_nil
    expect(record.reason_code).to be_nil
  end
end
